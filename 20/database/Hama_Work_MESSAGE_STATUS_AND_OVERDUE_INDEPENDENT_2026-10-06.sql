-- Hama Work - Independent Task Overdue + Per-user Message Status
-- 2026-10-06
-- Run after the existing project SQL patches.
-- Idempotent patch.

BEGIN;

/* ================================================================
   0) MESSAGE STATUS FIX NOTES
      - Status is per user, including the sender/GM.
      - A missing recipient row must NOT mean 'completed'.
      - set_message_recipient_status creates a personal status row
        for an authorized sender/GM when one does not exist.
   ================================================================ */

/* ================================================================
   1) TASK OVERDUE: derived state only; never mutate tasks.status
   ================================================================ */

CREATE OR REPLACE FUNCTION public.sync_task_due_notifications()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  t RECORD;
  v_user UUID;
  v_language TEXT;
BEGIN
  FOR t IN
    SELECT * FROM public.tasks
    WHERE status NOT IN ('completed','cancelled')
  LOOP
    -- IMPORTANT: overdue is derived from deadline. Do NOT write
    -- status='overdue' into tasks.status.

    IF t.deadline BETWEEN NOW() AND NOW() + INTERVAL '24 hours' THEN
      FOREACH v_user IN ARRAY ARRAY[
        t.responsible_id,
        t.follower_id
      ]::UUID[] LOOP
        IF v_user IS NOT NULL THEN
          SELECT COALESCE(preferred_language, 'ar')
            INTO v_language
          FROM public.profiles
          WHERE id = v_user;

          INSERT INTO public.notifications(
            user_id, type, title, body,
            target_type, target_id, dedupe_key
          )
          VALUES(
            v_user,
            'deadline',
            private.notification_title('deadline', NULL, v_language),
            t.title,
            'task',
            t.id,
            'deadline24:' || t.id::TEXT || ':' || v_user::TEXT
          )
          ON CONFLICT (dedupe_key) DO NOTHING;
        END IF;
      END LOOP;
    END IF;

    IF t.deadline < NOW() THEN
      FOREACH v_user IN ARRAY ARRAY[
        t.responsible_id,
        t.follower_id
      ]::UUID[] LOOP
        IF v_user IS NOT NULL THEN
          SELECT COALESCE(preferred_language, 'ar')
            INTO v_language
          FROM public.profiles
          WHERE id = v_user;

          INSERT INTO public.notifications(
            user_id, type, title, body,
            target_type, target_id, dedupe_key
          )
          VALUES(
            v_user,
            'overdue',
            private.notification_title('overdue', NULL, v_language),
            t.title,
            'task',
            t.id,
            'overdue:' || t.id::TEXT || ':' || v_user::TEXT
          )
          ON CONFLICT (dedupe_key) DO NOTHING;
        END IF;
      END LOOP;
    END IF;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_task_due_notifications() TO authenticated;

/* ================================================================
   2) PER-USER MESSAGE STATUS
      not_started | in_progress | completed
   ================================================================ */

ALTER TABLE public.message_recipients
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'not_started',
  ADD COLUMN IF NOT EXISTS status_updated_at TIMESTAMPTZ;

-- Normalize any unexpected/null legacy values.
UPDATE public.message_recipients
SET status = 'not_started'
WHERE status IS NULL
   OR status NOT IN ('not_started','in_progress','completed');

ALTER TABLE public.message_recipients
  ALTER COLUMN status SET DEFAULT 'not_started';

ALTER TABLE public.message_recipients
  DROP CONSTRAINT IF EXISTS message_recipients_status_check;

ALTER TABLE public.message_recipients
  ADD CONSTRAINT message_recipients_status_check
  CHECK (status IN ('not_started','in_progress','completed'));

CREATE INDEX IF NOT EXISTS idx_message_recipients_user_status
  ON public.message_recipients(user_id, status);

CREATE INDEX IF NOT EXISTS idx_message_recipients_message_user
  ON public.message_recipients(message_id, user_id);

/* New messages always start as not_started for each recipient. */
CREATE OR REPLACE FUNCTION public.set_message_recipient_status(
  p_message_id UUID,
  p_status TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_status NOT IN ('not_started','in_progress','completed') THEN
    RAISE EXCEPTION 'Invalid message status';
  END IF;

  -- First verify that the current user is allowed to see this message.
  -- GM and sender are allowed even if they do not have a recipient row.
  IF NOT (
    private.is_gm()
    OR EXISTS (
      SELECT 1
      FROM public.messages m
      WHERE m.id = p_message_id
        AND (
          m.created_by = auth.uid()
          OR EXISTS (
            SELECT 1
            FROM public.message_recipients rx
            WHERE rx.message_id = m.id
              AND rx.user_id = auth.uid()
          )
        )
    )
  ) THEN
    RAISE EXCEPTION 'Message recipient not found';
  END IF;

  -- Some legacy messages (and messages created by the current user) do not
  -- have a recipient row for the current user. Create the personal row so
  -- status can be changed normally.
  INSERT INTO public.message_recipients (message_id, user_id, status, status_updated_at)
  VALUES (p_message_id, auth.uid(), p_status, NOW())
  ON CONFLICT (message_id, user_id)
  DO UPDATE SET
    status = EXCLUDED.status,
    status_updated_at = EXCLUDED.status_updated_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_message_recipient_status(UUID, TEXT) TO authenticated;

/* ================================================================
   3) Visible messages: expose current user's status
      Every user's status is independent. If a personal status row does not yet
      exist (legacy message or sender/GM view), the UI starts at not_started.
   ================================================================ */

DROP FUNCTION IF EXISTS public.get_visible_messages();
CREATE OR REPLACE FUNCTION public.get_visible_messages()
RETURNS TABLE (
  id UUID,
  code TEXT,
  content TEXT,
  message_type TEXT,
  audience_type TEXT,
  created_by UUID,
  sender_name TEXT,
  sender_avatar_url TEXT,
  task_id UUID,
  created_at TIMESTAMPTZ,
  recipient_count INTEGER,
  seen_count INTEGER,
  seen_by_me BOOLEAN,
  my_status TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    m.id,
    m.code,
    m.content,
    m.message_type::TEXT,
    m.audience_type::TEXT,
    m.created_by,
    COALESCE(p.full_name, 'User'),
    p.avatar_url,
    m.task_id,
    m.created_at,
    COUNT(r.message_id)::INTEGER,
    COUNT(r.message_id) FILTER (WHERE r.seen_at IS NOT NULL)::INTEGER,
    COALESCE(BOOL_OR(r.user_id = auth.uid() AND r.seen_at IS NOT NULL), FALSE),
    COALESCE(
      MAX(rme.status) FILTER (WHERE rme.user_id = auth.uid()),
      'not_started'
    )
  FROM public.messages m
  LEFT JOIN public.profiles p ON p.id = m.created_by
  LEFT JOIN public.message_recipients r ON r.message_id = m.id
  LEFT JOIN public.message_recipients rme
    ON rme.message_id = m.id AND rme.user_id = auth.uid()
  WHERE private.is_gm()
     OR m.created_by = auth.uid()
     OR EXISTS (
       SELECT 1
       FROM public.message_recipients rx
       WHERE rx.message_id = m.id
         AND rx.user_id = auth.uid()
     )
  GROUP BY m.id, p.full_name, p.avatar_url
  ORDER BY m.created_at DESC
  LIMIT 200;
$$;

GRANT EXECUTE ON FUNCTION public.get_visible_messages() TO authenticated;

/* ================================================================
   4) Message status counters for the current user
   ================================================================ */

CREATE OR REPLACE FUNCTION public.get_my_message_status_counts()
RETURNS TABLE (
  not_started BIGINT,
  in_progress BIGINT,
  completed BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    COUNT(*) FILTER (WHERE COALESCE(r.status, 'not_started') = 'not_started'),
    COUNT(*) FILTER (WHERE COALESCE(r.status, 'not_started') = 'in_progress'),
    COUNT(*) FILTER (WHERE COALESCE(r.status, 'not_started') = 'completed')
  FROM public.messages m
  LEFT JOIN public.message_recipients r
    ON r.message_id = m.id AND r.user_id = auth.uid()
  WHERE private.is_gm()
     OR m.created_by = auth.uid()
     OR r.user_id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.get_my_message_status_counts() TO authenticated;

/* ================================================================
   5) Recipient detail RPC now returns status as well
   ================================================================ */

DROP FUNCTION IF EXISTS public.get_message_recipients(UUID);
CREATE OR REPLACE FUNCTION public.get_message_recipients(p_message_id UUID)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  username TEXT,
  avatar_url TEXT,
  seen_at TIMESTAMPTZ,
  status TEXT,
  status_updated_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    r.user_id,
    p.full_name,
    p.username,
    p.avatar_url,
    r.seen_at,
    r.status,
    r.status_updated_at
  FROM public.message_recipients r
  JOIN public.profiles p ON p.id = r.user_id
  WHERE r.message_id = p_message_id
    AND (
      private.is_gm()
      OR EXISTS (
        SELECT 1
        FROM public.messages m
        WHERE m.id = p_message_id
          AND (
            m.created_by = auth.uid()
            OR EXISTS (
              SELECT 1
              FROM public.message_recipients rx
              WHERE rx.message_id = m.id
                AND rx.user_id = auth.uid()
            )
          )
      )
    )
  ORDER BY p.full_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_message_recipients(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Hama Work Core reliability patch
-- Scope: Tasks + Messages + Notifications + Users support
-- Run AFTER Hama_Work_3_MODULES_FINAL.sql and the previous 3-module patch.
-- This patch is idempotent.

BEGIN;

-- 1) Guarantee task columns used by the Flutter client exist.
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS manager_confirmation_required BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS manager_confirmed BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS manager_confirmed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS manager_confirmed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS completion_requested_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS completed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reopened_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reopened_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

-- 2) Fix enum/text mismatch when changing task status.
CREATE OR REPLACE FUNCTION public.set_task_status(p_task_id UUID, p_status TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_task public.tasks%ROWTYPE;
  v_status public.task_status;
BEGIN
  SELECT * INTO v_task
  FROM public.tasks
  WHERE id = p_task_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Task not found';
  END IF;

  IF p_status NOT IN ('not_started','in_progress','ready_for_completion') THEN
    RAISE EXCEPTION 'Use the manager actions for completed/cancelled tasks';
  END IF;

  IF NOT (
    private.is_manager()
    OR v_task.responsible_id = auth.uid()
    OR v_task.follower_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  v_status := p_status::public.task_status;

  UPDATE public.tasks
  SET status = v_status,
      completion_requested_at = CASE
        WHEN v_status = 'ready_for_completion'::public.task_status THEN NOW()
        ELSE completion_requested_at
      END
  WHERE id = p_task_id;
END;
$$;

-- 3) Users must be visible to authenticated users; the app needs this for
-- assigning tasks and selecting message recipients.
DROP POLICY IF EXISTS profiles_select ON public.profiles;
CREATE POLICY profiles_select
ON public.profiles
FOR SELECT TO authenticated
USING (is_active = TRUE OR id = auth.uid());

GRANT SELECT ON public.profiles TO authenticated;

-- 4) Safe recipient RPC. No dependence on message_recipients.id.
CREATE OR REPLACE FUNCTION public.get_message_recipients(p_message_id UUID)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  username TEXT,
  seen_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT r.user_id, p.full_name, p.username, r.seen_at
  FROM public.message_recipients r
  JOIN public.profiles p ON p.id = r.user_id
  WHERE r.message_id = p_message_id
    AND (
      private.is_gm()
      OR EXISTS (
        SELECT 1 FROM public.messages m
        WHERE m.id = p_message_id
          AND (
            m.created_by = auth.uid()
            OR EXISTS (
              SELECT 1 FROM public.message_recipients rx
              WHERE rx.message_id = m.id AND rx.user_id = auth.uid()
            )
          )
      )
    )
  ORDER BY p.full_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_message_recipients(UUID) TO authenticated;

-- 5) Keep message reads safe and non-recursive.
CREATE OR REPLACE FUNCTION public.get_visible_messages()
RETURNS TABLE (
  id UUID,
  code TEXT,
  content TEXT,
  message_type TEXT,
  audience_type TEXT,
  created_by UUID,
  sender_name TEXT,
  task_id UUID,
  created_at TIMESTAMPTZ,
  recipient_count INTEGER,
  seen_count INTEGER,
  seen_by_me BOOLEAN
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
    COALESCE(p.full_name, 'User') AS sender_name,
    m.task_id,
    m.created_at,
    COUNT(r.message_id)::INTEGER,
    COUNT(r.message_id) FILTER (WHERE r.seen_at IS NOT NULL)::INTEGER,
    COALESCE(BOOL_OR(r.user_id = auth.uid() AND r.seen_at IS NOT NULL), FALSE)
  FROM public.messages m
  LEFT JOIN public.profiles p ON p.id = m.created_by
  LEFT JOIN public.message_recipients r ON r.message_id = m.id
  WHERE private.is_gm()
     OR m.created_by = auth.uid()
     OR EXISTS (
       SELECT 1 FROM public.message_recipients rx
       WHERE rx.message_id = m.id AND rx.user_id = auth.uid()
     )
  GROUP BY m.id, p.full_name
  ORDER BY m.created_at DESC
  LIMIT 200;
$$;

GRANT EXECUTE ON FUNCTION public.get_visible_messages() TO authenticated;

-- 6) Rebuild the task notification trigger with the enum value handled safely.
CREATE OR REPLACE FUNCTION private.notify_task_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user UUID;
BEGIN
  IF TG_OP = 'INSERT' THEN
    FOREACH v_user IN ARRAY ARRAY[NEW.responsible_id, NEW.follower_id]::UUID[] LOOP
      IF v_user IS NOT NULL AND v_user <> NEW.created_by THEN
        INSERT INTO public.notifications(
          user_id, type, title, body, target_type, target_id, dedupe_key
        )
        VALUES(
          v_user, 'task_created', 'New Task', NEW.title, 'task', NEW.id,
          'task_created:' || NEW.id::TEXT || ':' || v_user::TEXT
        )
        ON CONFLICT (dedupe_key) DO NOTHING;
      END IF;
    END LOOP;
  ELSIF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    FOREACH v_user IN ARRAY ARRAY[NEW.responsible_id, NEW.follower_id, NEW.created_by]::UUID[] LOOP
      IF v_user IS NOT NULL AND v_user <> auth.uid() THEN
        INSERT INTO public.notifications(
          user_id, type, title, body, target_type, target_id, dedupe_key
        )
        VALUES(
          v_user, 'task_status', 'Task Status Updated', NEW.title, 'task', NEW.id,
          'task_status:' || NEW.id::TEXT || ':' || NEW.status::TEXT || ':' || v_user::TEXT
        )
        ON CONFLICT (dedupe_key) DO NOTHING;
      END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tasks_notify_changes ON public.tasks;
CREATE TRIGGER tasks_notify_changes
AFTER INSERT OR UPDATE OF status, responsible_id, follower_id ON public.tasks
FOR EACH ROW EXECUTE FUNCTION private.notify_task_change();

-- 7) Make sure notification reads work.
GRANT SELECT, UPDATE, DELETE ON public.notifications TO authenticated;

-- 8) Force PostgREST to reload the schema cache.
NOTIFY pgrst, 'reload schema';

COMMIT;

-- Verification
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema='public'
  AND table_name='tasks'
  AND column_name IN ('status','manager_confirmed','manager_confirmation_required')
ORDER BY column_name;

SELECT COUNT(*) AS active_users
FROM public.profiles
WHERE is_active = TRUE;

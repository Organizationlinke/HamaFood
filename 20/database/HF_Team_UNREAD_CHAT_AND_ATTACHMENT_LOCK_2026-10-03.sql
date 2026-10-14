-- HF Team: unread task/message chat counters + lock attachments after daily-log save
-- Idempotent.
BEGIN;

/* ================================================================
   1) Per-user read markers for task chat and external message replies
   ================================================================ */
CREATE TABLE IF NOT EXISTS public.task_comment_reads (
  task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  last_read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (task_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.message_comment_reads (
  message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  last_read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id)
);

ALTER TABLE public.task_comment_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_comment_reads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_comment_reads_self ON public.task_comment_reads;
CREATE POLICY task_comment_reads_self ON public.task_comment_reads
FOR ALL TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS message_comment_reads_self ON public.message_comment_reads;
CREATE POLICY message_comment_reads_self ON public.message_comment_reads
FOR ALL TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

GRANT SELECT, INSERT, UPDATE ON public.task_comment_reads TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.message_comment_reads TO authenticated;

/* ================================================================
   2) Task chat unread count / mark read
   ================================================================ */
CREATE OR REPLACE FUNCTION public.get_unread_task_comment_count(p_task_id UUID)
RETURNS INTEGER
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)::INTEGER
  FROM public.task_comments c
  WHERE c.task_id = p_task_id
    AND c.created_by <> auth.uid()
    AND private.can_access_task(p_task_id)
    AND c.created_at > COALESCE(
      (SELECT r.last_read_at
       FROM public.task_comment_reads r
       WHERE r.task_id = p_task_id AND r.user_id = auth.uid()),
      'epoch'::timestamptz
    );
$$;

CREATE OR REPLACE FUNCTION public.mark_task_comments_read(p_task_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT private.can_access_task(p_task_id) THEN
    RAISE EXCEPTION 'Task access denied';
  END IF;

  INSERT INTO public.task_comment_reads(task_id, user_id, last_read_at)
  VALUES (p_task_id, auth.uid(), NOW())
  ON CONFLICT (task_id, user_id)
  DO UPDATE SET last_read_at = EXCLUDED.last_read_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_unread_task_comment_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_task_comments_read(UUID) TO authenticated;

/* ================================================================
   3) External message reply unread counts / mark read
   ================================================================ */
CREATE OR REPLACE FUNCTION public.get_unread_message_comment_counts()
RETURNS TABLE(message_id UUID, unread_count INTEGER)
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.message_id, COUNT(*)::INTEGER
  FROM public.message_comments c
  JOIN public.messages m ON m.id = c.message_id
  WHERE c.created_by <> auth.uid()
    AND private.can_access_message(c.message_id)
    AND c.created_at > COALESCE(
      (SELECT r.last_read_at
       FROM public.message_comment_reads r
       WHERE r.message_id = c.message_id AND r.user_id = auth.uid()),
      'epoch'::timestamptz
    )
  GROUP BY c.message_id;
$$;

CREATE OR REPLACE FUNCTION public.get_unread_message_conversations_count()
RETURNS INTEGER
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)::INTEGER
  FROM (
    SELECT c.message_id
    FROM public.message_comments c
    WHERE c.created_by <> auth.uid()
      AND private.can_access_message(c.message_id)
      AND c.created_at > COALESCE(
        (SELECT r.last_read_at
         FROM public.message_comment_reads r
         WHERE r.message_id = c.message_id AND r.user_id = auth.uid()),
        'epoch'::timestamptz
      )
    GROUP BY c.message_id
  ) x;
$$;

CREATE OR REPLACE FUNCTION public.mark_message_comments_read(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT private.can_access_message(p_message_id) THEN
    RAISE EXCEPTION 'Message access denied';
  END IF;

  INSERT INTO public.message_comment_reads(message_id, user_id, last_read_at)
  VALUES (p_message_id, auth.uid(), NOW())
  ON CONFLICT (message_id, user_id)
  DO UPDATE SET last_read_at = EXCLUDED.last_read_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_unread_message_comment_counts() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_unread_message_conversations_count() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_message_comments_read(UUID) TO authenticated;

/* ================================================================
   4) Daily Work Log attachments: only during creation workflow.
      Existing/saved logs are locked.
   ================================================================ */
ALTER TABLE public.task_daily_updates
  ADD COLUMN IF NOT EXISTS attachments_locked BOOLEAN NOT NULL DEFAULT FALSE;

-- Existing records are already saved; lock them immediately.
UPDATE public.task_daily_updates
SET attachments_locked = TRUE
WHERE attachments_locked = FALSE;

CREATE OR REPLACE FUNCTION public.finalize_daily_update_attachments(p_daily_update_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_created_by UUID;
  v_task_id UUID;
BEGIN
  SELECT d.created_by, d.task_id
    INTO v_created_by, v_task_id
  FROM public.task_daily_updates d
  WHERE d.id = p_daily_update_id;

  IF v_created_by IS NULL THEN
    RAISE EXCEPTION 'Daily work record not found';
  END IF;

  IF NOT (
    v_created_by = auth.uid()
    OR private.is_gm()
    OR private.is_manager()
  ) THEN
    RAISE EXCEPTION 'Not allowed to finalize this work log';
  END IF;

  UPDATE public.task_daily_updates
  SET attachments_locked = TRUE,
      updated_at = NOW()
  WHERE id = p_daily_update_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.finalize_daily_update_attachments(UUID) TO authenticated;

DROP POLICY IF EXISTS attachments_insert ON public.attachments;
CREATE POLICY attachments_insert ON public.attachments
FOR INSERT TO authenticated
WITH CHECK (
  uploaded_by = auth.uid()
  AND (
    (
      task_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.tasks t
        WHERE t.id = task_id
          AND t.deleted_at IS NULL
          AND t.status <> 'completed'::public.task_status
          AND (private.is_gm() OR private.is_manager() OR t.responsible_id = auth.uid())
      )
    )
    OR
    (
      daily_update_id IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.task_daily_updates d
        JOIN public.tasks t ON t.id = d.task_id
        WHERE d.id = daily_update_id
          AND d.attachments_locked = FALSE
          AND t.deleted_at IS NULL
          AND t.status = 'in_progress'::public.task_status
          AND (private.is_gm() OR private.is_manager() OR t.responsible_id = auth.uid() OR t.follower_id = auth.uid())
      )
    )
    OR
    (
      task_comment_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.task_comments c
        JOIN public.tasks t ON t.id = c.task_id
        WHERE c.id = task_comment_id
          AND t.deleted_at IS NULL
          AND t.status <> 'completed'::public.task_status
          AND (private.is_gm() OR private.is_manager() OR t.responsible_id = auth.uid() OR t.follower_id = auth.uid())
      )
    )
    OR
    (message_id IS NOT NULL AND private.can_access_message(message_id))
    OR
    (
      message_comment_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.message_comments c
        WHERE c.id = message_comment_id
          AND private.can_access_message(c.message_id)
      )
    )
  )
);

COMMIT;

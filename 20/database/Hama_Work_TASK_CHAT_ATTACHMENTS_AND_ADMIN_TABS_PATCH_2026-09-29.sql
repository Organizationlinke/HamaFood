-- Hama Work follow-up patch 2026-09-29
-- Adds task-chat attachments and completes the task-detail behavior.
-- Run AFTER the fixed SECURITY_ATTACHMENTS_DAILY_REPLY_PROOF patch.

BEGIN;

/* ================================================================
   1) ATTACHMENTS FOR TASK CHAT COMMENTS
   ================================================================ */

ALTER TABLE public.attachments
  ADD COLUMN IF NOT EXISTS task_comment_id UUID
    REFERENCES public.task_comments(id) ON DELETE CASCADE;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'attachments_one_parent'
      AND conrelid = 'public.attachments'::regclass
  ) THEN
    ALTER TABLE public.attachments DROP CONSTRAINT attachments_one_parent;
  END IF;
END $$;

ALTER TABLE public.attachments
  ADD CONSTRAINT attachments_one_parent
  CHECK (
    (CASE WHEN task_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN message_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN daily_update_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN message_comment_id IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN task_comment_id IS NOT NULL THEN 1 ELSE 0 END) = 1
  );

CREATE INDEX IF NOT EXISTS attachments_task_comment_idx
  ON public.attachments(task_comment_id, created_at DESC);

/* ================================================================
   2) RLS FOR TASK-CHAT ATTACHMENTS
   ================================================================ */

DROP POLICY IF EXISTS attachments_select ON public.attachments;
DROP POLICY IF EXISTS attachments_insert ON public.attachments;

CREATE POLICY attachments_select
ON public.attachments
FOR SELECT
TO authenticated
USING (
  (
    task_id IS NOT NULL
    AND private.can_access_task(task_id)
  )
  OR (
    message_id IS NOT NULL
    AND private.can_access_message(message_id)
  )
  OR (
    daily_update_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.task_daily_updates AS d
      WHERE d.id = public.attachments.daily_update_id
        AND private.can_access_task(d.task_id)
    )
  )
  OR (
    message_comment_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.message_comments AS c
      WHERE c.id = public.attachments.message_comment_id
        AND private.can_access_message(c.message_id)
    )
  )
  OR (
    task_comment_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.task_comments AS c
      WHERE c.id = public.attachments.task_comment_id
        AND private.can_access_task(c.task_id)
    )
  )
);

CREATE POLICY attachments_insert
ON public.attachments
FOR INSERT
TO authenticated
WITH CHECK (
  uploaded_by = auth.uid()
  AND (
    (
      task_id IS NOT NULL
      AND private.can_access_task(task_id)
    )
    OR (
      message_id IS NOT NULL
      AND private.can_access_message(message_id)
    )
    OR (
      daily_update_id IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.task_daily_updates AS d
        WHERE d.id = public.attachments.daily_update_id
          AND private.can_access_task(d.task_id)
      )
    )
    OR (
      message_comment_id IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.message_comments AS c
        WHERE c.id = public.attachments.message_comment_id
          AND private.can_access_message(c.message_id)
      )
    )
    OR (
      task_comment_id IS NOT NULL
      AND private.can_access_task(
        (SELECT c.task_id FROM public.task_comments AS c WHERE c.id = public.attachments.task_comment_id)
      )
    )
  )
);

/* ================================================================
   3) SIGNED URL ACCESS FOR TASK-CHAT ATTACHMENTS
   ================================================================ */

CREATE OR REPLACE FUNCTION public.attachment_signed_url(p_attachment_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_path TEXT;
  v_task UUID;
  v_message UUID;
  v_daily_update UUID;
  v_message_comment UUID;
  v_task_comment UUID;
  v_url TEXT;
BEGIN
  SELECT
    storage_path,
    task_id,
    message_id,
    daily_update_id,
    message_comment_id,
    task_comment_id
  INTO
    v_path,
    v_task,
    v_message,
    v_daily_update,
    v_message_comment,
    v_task_comment
  FROM public.attachments
  WHERE id = p_attachment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Attachment not found';
  END IF;

  IF NOT (
    (v_task IS NOT NULL AND private.can_access_task(v_task))
    OR (v_message IS NOT NULL AND private.can_access_message(v_message))
    OR (
      v_daily_update IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.task_daily_updates AS d
        WHERE d.id = v_daily_update
          AND private.can_access_task(d.task_id)
      )
    )
    OR (
      v_message_comment IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.message_comments AS c
        WHERE c.id = v_message_comment
          AND private.can_access_message(c.message_id)
      )
    )
    OR (
      v_task_comment IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.task_comments AS c
        WHERE c.id = v_task_comment
          AND private.can_access_task(c.task_id)
      )
    )
  ) THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  SELECT storage.sign(v_path, 'attachments', 3600)
    INTO v_url;

  RETURN v_url;
END;
$$;

GRANT EXECUTE
ON FUNCTION public.attachment_signed_url(UUID)
TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

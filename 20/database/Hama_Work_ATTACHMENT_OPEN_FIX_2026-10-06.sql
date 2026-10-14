/*
  Hama Work - Attachment Open Fix
  2026-10-06

  Purpose:
  1) Keep signed URL generation centralized in a SECURITY DEFINER RPC.
  2) Support all current attachment parents: task, message, daily update,
     message comment and task comment.

  The Flutter client calls attachment_signed_url(id) instead of directly
  calling storage.createSignedUrl().
*/

BEGIN;

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

  IF v_url IS NULL OR BTRIM(v_url) = '' THEN
    RAISE EXCEPTION 'Could not create attachment signed URL';
  END IF;

  RETURN v_url;
END;
$$;

GRANT EXECUTE
ON FUNCTION public.attachment_signed_url(UUID)
TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

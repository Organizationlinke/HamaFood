-- Hama Work next security + attachments patch
-- Run AFTER the currently working Hama Work core/admin/activity patches.
BEGIN;

-- 1) Explicit action permissions. These are separate so reopening/evaluating
-- cannot accidentally be inherited from a broad manager role.
INSERT INTO public.user_permissions(user_id, permission_key, enabled)
SELECT p.id, x.permission_key,
       CASE WHEN p.role = 'gm' OR x.permission_key IN ('tasks.start','tasks.request_completion','attachments.upload') THEN TRUE ELSE FALSE END
FROM public.profiles p
CROSS JOIN (VALUES
  ('tasks.start'),('tasks.request_completion'),('tasks.confirm_completion'),
  ('tasks.reopen'),('tasks.evaluate'),('tasks.cancel'),('tasks.manage_status'),
  ('attachments.upload')
) x(permission_key)
ON CONFLICT (user_id, permission_key) DO NOTHING;

-- 2) Status changes: only an explicit status-management permission (or GM)
-- may start/request completion. Completed/cancelled remain separate actions.
CREATE OR REPLACE FUNCTION public.set_task_status(p_task_id UUID, p_status TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_task public.tasks%ROWTYPE;
  v_allowed BOOLEAN;
BEGIN
  SELECT * INTO v_task FROM public.tasks WHERE id=p_task_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found'; END IF;
  IF p_status NOT IN ('not_started','in_progress','ready_for_completion') THEN
    RAISE EXCEPTION 'Use the manager actions for completed/cancelled tasks';
  END IF;
  SELECT private.is_gm() OR
    COALESCE((SELECT enabled FROM public.user_permissions WHERE user_id=auth.uid() AND permission_key='tasks.manage_status'),FALSE) OR
    (p_status='in_progress' AND COALESCE((SELECT enabled FROM public.user_permissions WHERE user_id=auth.uid() AND permission_key='tasks.start'),FALSE)) OR
    (p_status='ready_for_completion' AND COALESCE((SELECT enabled FROM public.user_permissions WHERE user_id=auth.uid() AND permission_key='tasks.request_completion'),FALSE))
    INTO v_allowed;
  IF NOT v_allowed THEN RAISE EXCEPTION 'Task status permission required'; END IF;
  IF NOT (v_task.responsible_id=auth.uid() OR v_task.follower_id=auth.uid() OR private.is_gm() OR private.is_manager()) THEN
    RAISE EXCEPTION 'You are not assigned to this task';
  END IF;
  UPDATE public.tasks SET status=p_status::public.task_status,
    completion_requested_at=CASE WHEN p_status='ready_for_completion' THEN NOW() ELSE completion_requested_at END,
    updated_at=NOW() WHERE id=p_task_id;
END; $$;
GRANT EXECUTE ON FUNCTION public.set_task_status(UUID,TEXT) TO authenticated;

-- 3) Reopen/evaluate/confirm/cancel must each have explicit permission.
CREATE OR REPLACE FUNCTION public.reopen_task(p_task_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NOT (private.is_gm() OR COALESCE((SELECT enabled FROM public.user_permissions WHERE user_id=auth.uid() AND permission_key='tasks.reopen'),FALSE)) THEN
    RAISE EXCEPTION 'Reopen task permission required';
  END IF;
  UPDATE public.tasks SET status='in_progress'::public.task_status, manager_confirmed=FALSE, updated_at=NOW(), reopened_at=NOW(), reopened_by=auth.uid()
  WHERE id=p_task_id AND deleted_at IS NULL AND status='completed'::public.task_status;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found or not completed'; END IF;
END; $$;
GRANT EXECUTE ON FUNCTION public.reopen_task(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.confirm_task(p_task_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NOT (private.is_gm() OR COALESCE((SELECT enabled FROM public.user_permissions WHERE user_id=auth.uid() AND permission_key='tasks.confirm_completion'),FALSE)) THEN
    RAISE EXCEPTION 'Confirm completion permission required';
  END IF;
  UPDATE public.tasks SET status='completed'::public.task_status, manager_confirmed=TRUE, manager_confirmed_by=auth.uid(), manager_confirmed_at=NOW(), completed_at=NOW(), completed_by=auth.uid(), updated_at=NOW()
  WHERE id=p_task_id AND deleted_at IS NULL AND status='ready_for_completion'::public.task_status;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not ready for completion'; END IF;
END; $$;
GRANT EXECUTE ON FUNCTION public.confirm_task(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.evaluate_task(p_task_id UUID, p_score INTEGER, p_comment TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NOT (private.is_gm() OR COALESCE((SELECT enabled FROM public.user_permissions WHERE user_id=auth.uid() AND permission_key='tasks.evaluate'),FALSE)) THEN
    RAISE EXCEPTION 'Evaluate task permission required';
  END IF;
  IF p_score < 1 OR p_score > 10 THEN RAISE EXCEPTION 'Score must be between 1 and 10'; END IF;
  UPDATE public.tasks SET score=p_score, eval_comment=NULLIF(BTRIM(p_comment),''), updated_at=NOW() WHERE id=p_task_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found'; END IF;
END; $$;
GRANT EXECUTE ON FUNCTION public.evaluate_task(UUID,INTEGER,TEXT) TO authenticated;

-- 4) Private attachments bucket. Files are accessed through short-lived signed URLs.
INSERT INTO storage.buckets(id,name,public) VALUES('attachments','attachments',FALSE)
ON CONFLICT(id) DO UPDATE SET public=FALSE;

CREATE TABLE IF NOT EXISTS public.attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE,
  message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
  file_name TEXT NOT NULL,
  storage_path TEXT NOT NULL UNIQUE,
  mime_type TEXT,
  file_size BIGINT,
  uploaded_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT attachments_one_parent CHECK ((task_id IS NOT NULL) <> (message_id IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS attachments_task_idx ON public.attachments(task_id,created_at DESC);
CREATE INDEX IF NOT EXISTS attachments_message_idx ON public.attachments(message_id,created_at DESC);
ALTER TABLE public.attachments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS attachments_select ON public.attachments;
DROP POLICY IF EXISTS attachments_insert ON public.attachments;
DROP POLICY IF EXISTS attachments_delete ON public.attachments;
CREATE POLICY attachments_select ON public.attachments FOR SELECT TO authenticated
USING ((task_id IS NOT NULL AND private.can_access_task(task_id)) OR (message_id IS NOT NULL AND private.can_access_message(message_id)));
CREATE POLICY attachments_insert ON public.attachments FOR INSERT TO authenticated
WITH CHECK (uploaded_by=auth.uid() AND ((task_id IS NOT NULL AND private.can_access_task(task_id)) OR (message_id IS NOT NULL AND private.can_access_message(message_id))));
CREATE POLICY attachments_delete ON public.attachments FOR DELETE TO authenticated
USING (uploaded_by=auth.uid() OR private.is_gm());
GRANT SELECT,INSERT,DELETE ON public.attachments TO authenticated;

DROP POLICY IF EXISTS attachments_storage_select ON storage.objects;
DROP POLICY IF EXISTS attachments_storage_insert ON storage.objects;
DROP POLICY IF EXISTS attachments_storage_delete ON storage.objects;
CREATE POLICY attachments_storage_select ON storage.objects FOR SELECT TO authenticated
USING (bucket_id='attachments');
CREATE POLICY attachments_storage_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id='attachments' AND (storage.foldername(name))[1]=auth.uid()::text);
CREATE POLICY attachments_storage_delete ON storage.objects FOR DELETE TO authenticated
USING (bucket_id='attachments' AND ((storage.foldername(name))[1]=auth.uid()::text OR private.is_gm()));

-- Helper RPC for short-lived download URLs.
CREATE OR REPLACE FUNCTION public.attachment_signed_url(p_attachment_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_path TEXT; v_task UUID; v_message UUID; v_url TEXT;
BEGIN
  SELECT storage_path,task_id,message_id INTO v_path,v_task,v_message FROM public.attachments WHERE id=p_attachment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Attachment not found'; END IF;
  IF NOT ((v_task IS NOT NULL AND private.can_access_task(v_task)) OR (v_message IS NOT NULL AND private.can_access_message(v_message))) THEN RAISE EXCEPTION 'Not allowed'; END IF;
  SELECT storage.sign(v_path, 'attachments', 3600) INTO v_url;
  RETURN v_url;
END; $$;
GRANT EXECUTE ON FUNCTION public.attachment_signed_url(UUID) TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;

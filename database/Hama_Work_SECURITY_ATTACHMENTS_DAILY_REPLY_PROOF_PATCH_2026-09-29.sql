-- Hama Work: daily/reply attachments + evidence enforcement + deleted notification cleanup
BEGIN;

ALTER TABLE public.attachments ADD COLUMN IF NOT EXISTS daily_update_id UUID REFERENCES public.task_daily_updates(id) ON DELETE CASCADE;
ALTER TABLE public.attachments ADD COLUMN IF NOT EXISTS message_comment_id UUID REFERENCES public.message_comments(id) ON DELETE CASCADE;
ALTER TABLE public.attachments ADD COLUMN IF NOT EXISTS is_completion_proof BOOLEAN NOT NULL DEFAULT FALSE;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname='attachments_one_parent' AND conrelid='public.attachments'::regclass) THEN ALTER TABLE public.attachments DROP CONSTRAINT attachments_one_parent; END IF; END $$;
ALTER TABLE public.attachments ADD CONSTRAINT attachments_one_parent CHECK (((task_id IS NOT NULL)::int + (message_id IS NOT NULL)::int + (daily_update_id IS NOT NULL)::int + (message_comment_id IS NOT NULL)::int) = 1);
CREATE INDEX IF NOT EXISTS attachments_daily_update_idx ON public.attachments(daily_update_id,created_at DESC);
CREATE INDEX IF NOT EXISTS attachments_message_comment_idx ON public.attachments(message_comment_id,created_at DESC);

ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS completion_proof_note TEXT;

CREATE OR REPLACE FUNCTION public.set_task_status(p_task_id UUID, p_status TEXT, p_proof_note TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_task public.tasks%ROWTYPE; v_allowed BOOLEAN; v_note TEXT; v_has_proof BOOLEAN;
BEGIN
 SELECT * INTO v_task FROM public.tasks WHERE id=p_task_id FOR UPDATE;
 IF NOT FOUND OR v_task.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Task not found'; END IF;
 IF p_status NOT IN ('not_started','in_progress','ready_for_completion') THEN RAISE EXCEPTION 'Use the manager actions for completed/cancelled tasks'; END IF;
 SELECT private.is_gm() OR COALESCE((SELECT enabled FROM public.user_permissions WHERE user_id=auth.uid() AND permission_key='tasks.manage_status'),FALSE) OR (p_status='in_progress' AND COALESCE((SELECT enabled FROM public.user_permissions WHERE user_id=auth.uid() AND permission_key='tasks.start'),FALSE)) OR (p_status='ready_for_completion' AND COALESCE((SELECT enabled FROM public.user_permissions WHERE user_id=auth.uid() AND permission_key='tasks.request_completion'),FALSE)) INTO v_allowed;
 IF NOT v_allowed THEN RAISE EXCEPTION 'Task status permission required'; END IF;
 IF NOT (v_task.responsible_id=auth.uid() OR v_task.follower_id=auth.uid() OR private.is_gm() OR private.is_manager()) THEN RAISE EXCEPTION 'You are not assigned to this task'; END IF;
 v_note:=NULLIF(BTRIM(p_proof_note),'');
 IF p_status='ready_for_completion' AND v_task.evidence_required THEN
   SELECT EXISTS(SELECT 1 FROM public.attachments a WHERE a.task_id=p_task_id AND a.is_completion_proof) INTO v_has_proof;
   IF v_note IS NULL AND NOT v_has_proof AND NULLIF(BTRIM(v_task.completion_proof_note),'') IS NULL THEN RAISE EXCEPTION 'Completion proof is required: add a note or attachment'; END IF;
 END IF;
 UPDATE public.tasks SET status=p_status::public.task_status, completion_requested_at=CASE WHEN p_status='ready_for_completion' THEN NOW() ELSE completion_requested_at END, completion_proof_note=COALESCE(v_note,completion_proof_note), updated_at=NOW() WHERE id=p_task_id;
END; $$;
GRANT EXECUTE ON FUNCTION public.set_task_status(UUID,TEXT,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_task(p_task_id UUID) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT private.is_gm() THEN RAISE EXCEPTION 'Only the General Manager can delete tasks'; END IF;
 UPDATE public.tasks SET deleted_from_status=status,deleted_at=NOW(),deleted_by=auth.uid(),updated_at=NOW() WHERE id=p_task_id AND deleted_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Task not found or already deleted'; END IF;
 DELETE FROM public.notifications WHERE target_type='task' AND target_id=p_task_id;
END; $$;
GRANT EXECUTE ON FUNCTION public.admin_delete_task(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION private.notify_task_change() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_user UUID; v_actor_name TEXT; v_action TEXT;
BEGIN
 IF NEW.deleted_at IS NOT NULL THEN RETURN NEW; END IF;
 SELECT COALESCE(p.full_name,'User') INTO v_actor_name FROM public.profiles p WHERE p.id=auth.uid();
 IF TG_OP='INSERT' THEN
  FOREACH v_user IN ARRAY ARRAY[NEW.responsible_id,NEW.follower_id]::UUID[] LOOP IF v_user IS NOT NULL AND v_user<>NEW.created_by THEN INSERT INTO public.notifications(user_id,type,title,body,target_type,target_id,dedupe_key,actor_id) VALUES(v_user,'task_created','New Task',COALESCE(v_actor_name,'System')||' created the task: '||NEW.title,'task',NEW.id,'task_created:'||NEW.id::TEXT||':'||v_user::TEXT,auth.uid()) ON CONFLICT(dedupe_key) DO NOTHING; END IF; END LOOP;
 ELSIF TG_OP='UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
  v_action:=CASE NEW.status::TEXT WHEN 'in_progress' THEN 'started the task' WHEN 'ready_for_completion' THEN 'requested completion for the task' WHEN 'completed' THEN 'completed the task' WHEN 'cancelled' THEN 'cancelled the task' WHEN 'not_started' THEN 'returned the task to Not Started' ELSE 'changed the task status to '||NEW.status::TEXT END;
  FOREACH v_user IN ARRAY ARRAY[NEW.responsible_id,NEW.follower_id,NEW.created_by]::UUID[] LOOP IF v_user IS NOT NULL AND v_user<>auth.uid() THEN INSERT INTO public.notifications(user_id,type,title,body,target_type,target_id,dedupe_key,actor_id) VALUES(v_user,'task_status','Task Update',COALESCE(v_actor_name,'System')||' '||v_action||': '||NEW.title,'task',NEW.id,'task_status:'||NEW.id::TEXT||':'||NEW.status::TEXT||':'||v_user::TEXT,auth.uid()) ON CONFLICT(dedupe_key) DO NOTHING; END IF; END LOOP;
 END IF; RETURN NEW;
END; $$;

DROP POLICY IF EXISTS attachments_select ON public.attachments;
DROP POLICY IF EXISTS attachments_insert ON public.attachments;
CREATE POLICY attachments_select ON public.attachments FOR SELECT TO authenticated USING ((task_id IS NOT NULL AND private.can_access_task(task_id)) OR (message_id IS NOT NULL AND private.can_access_message(message_id)) OR (daily_update_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.task_daily_updates d WHERE d.id=daily_update_id AND private.can_access_task(d.task_id))) OR (message_comment_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.message_comments c WHERE c.id=message_comment_id AND private.can_access_message(c.message_id))));
CREATE POLICY attachments_insert ON public.attachments FOR INSERT TO authenticated WITH CHECK (uploaded_by=auth.uid() AND ((task_id IS NOT NULL AND private.can_access_task(task_id)) OR (message_id IS NOT NULL AND private.can_access_message(message_id)) OR (daily_update_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.task_daily_updates d WHERE d.id=daily_update_id AND private.can_access_task(d.task_id))) OR (message_comment_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.message_comments c WHERE c.id=message_comment_id AND private.can_access_message(c.message_id))));

NOTIFY pgrst,'reload schema';
COMMIT;

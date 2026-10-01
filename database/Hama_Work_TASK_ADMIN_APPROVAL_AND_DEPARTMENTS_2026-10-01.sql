-- HF Team: Admin approval as the final completion step
-- Workflow:
-- 1) Start                -> Responsible
-- 2) Request completion   -> Responsible
-- 3) Follow-up completed  -> Follower (when assigned)
-- 4) Approve operation    -> General Manager (Admin)
--
-- Also adds the awaiting_approval task status.
-- Run AFTER Hama_Work_TASK_FOLLOWER_REVIEW_MOBILE_2026-10-01.sql
-- Idempotent.

BEGIN;

/* ================================================================
   0) Review audit fields (safe if already present)
   ================================================================ */
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS follower_reviewed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS follower_reviewed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

/* ================================================================
   1) New intermediate status
   ================================================================ */
ALTER TYPE public.task_status
  ADD VALUE IF NOT EXISTS 'awaiting_approval';

/* ================================================================
   2) Status function: start / request completion only
   ================================================================ */
CREATE OR REPLACE FUNCTION public.set_task_status(
  p_task_id UUID,
  p_status TEXT,
  p_proof_note TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_task public.tasks%ROWTYPE;
  v_allowed BOOLEAN;
  v_note TEXT;
  v_has_proof BOOLEAN;
BEGIN
  SELECT * INTO v_task
  FROM public.tasks
  WHERE id = p_task_id
  FOR UPDATE;

  IF NOT FOUND OR v_task.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Task not found';
  END IF;

  IF p_status NOT IN ('not_started','in_progress','ready_for_completion') THEN
    RAISE EXCEPTION 'Use the workflow actions for completion and approval';
  END IF;

  SELECT
      (p_status='in_progress'
        AND COALESCE((SELECT enabled FROM public.user_permissions
                      WHERE user_id=auth.uid() AND permission_key='tasks.start'),FALSE))
      OR
      (p_status='ready_for_completion'
        AND COALESCE((SELECT enabled FROM public.user_permissions
                      WHERE user_id=auth.uid() AND permission_key='tasks.request_completion'),FALSE))
    INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Task status permission required';
  END IF;

  IF v_task.responsible_id <> auth.uid() THEN
    RAISE EXCEPTION 'Only the responsible person can perform this action';
  END IF;

  v_note := NULLIF(BTRIM(p_proof_note),'');

  IF p_status='ready_for_completion' AND v_task.evidence_required THEN
    SELECT EXISTS(
      SELECT 1 FROM public.attachments a
      WHERE a.task_id=p_task_id AND a.is_completion_proof
    ) INTO v_has_proof;

    IF v_note IS NULL
       AND NOT v_has_proof
       AND NULLIF(BTRIM(v_task.completion_proof_note),'') IS NULL THEN
      RAISE EXCEPTION 'Completion proof is required: add a note or attachment';
    END IF;
  END IF;

  UPDATE public.tasks
  SET status=p_status::public.task_status,
      completion_requested_at=CASE
        WHEN p_status='ready_for_completion' THEN NOW()
        ELSE completion_requested_at
      END,
      completion_proof_note=COALESCE(v_note,completion_proof_note),
      follower_reviewed_at=CASE
        WHEN p_status='ready_for_completion' THEN NULL
        ELSE follower_reviewed_at
      END,
      follower_reviewed_by=CASE
        WHEN p_status='ready_for_completion' THEN NULL
        ELSE follower_reviewed_by
      END,
      manager_confirmed=CASE
        WHEN p_status IN ('not_started','in_progress','ready_for_completion') THEN FALSE
        ELSE manager_confirmed
      END,
      manager_confirmed_by=CASE
        WHEN p_status IN ('not_started','in_progress','ready_for_completion') THEN NULL
        ELSE manager_confirmed_by
      END,
      manager_confirmed_at=CASE
        WHEN p_status IN ('not_started','in_progress','ready_for_completion') THEN NULL
        ELSE manager_confirmed_at
      END,
      updated_at=NOW()
  WHERE id=p_task_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_task_status(UUID,TEXT,TEXT) TO authenticated;

/* ================================================================
   3) Follower review: does NOT complete the task.
      It moves the task to awaiting_approval.
   ================================================================ */
CREATE OR REPLACE FUNCTION public.review_task_completion(p_task_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_task public.tasks%ROWTYPE;
BEGIN
  SELECT * INTO v_task
  FROM public.tasks
  WHERE id=p_task_id
  FOR UPDATE;

  IF NOT FOUND OR v_task.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Task not found';
  END IF;

  IF v_task.follower_id IS NULL OR v_task.follower_id <> auth.uid() THEN
    RAISE EXCEPTION 'Only the assigned follower can review this task';
  END IF;

  IF v_task.status <> 'ready_for_completion'::public.task_status THEN
    RAISE EXCEPTION 'Task is not waiting for follower review';
  END IF;

  UPDATE public.tasks
  SET status='awaiting_approval'::public.task_status,
      follower_reviewed_at=NOW(),
      follower_reviewed_by=auth.uid(),
      manager_confirmed=FALSE,
      manager_confirmed_by=NULL,
      manager_confirmed_at=NULL,
      updated_at=NOW()
  WHERE id=p_task_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.review_task_completion(UUID) TO authenticated;

/* ================================================================
   4) Admin approval: General Manager only.
      - With follower: must be awaiting_approval.
      - Without follower: admin can approve directly after request.
   ================================================================ */
CREATE OR REPLACE FUNCTION public.approve_task(p_task_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_task public.tasks%ROWTYPE;
BEGIN
  IF NOT private.is_gm() THEN
    RAISE EXCEPTION 'Only the General Manager can approve the operation';
  END IF;

  SELECT * INTO v_task
  FROM public.tasks
  WHERE id=p_task_id
  FOR UPDATE;

  IF NOT FOUND OR v_task.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Task not found';
  END IF;

  IF v_task.follower_id IS NOT NULL THEN
    IF v_task.status <> 'awaiting_approval'::public.task_status THEN
      RAISE EXCEPTION 'Follower review is required before admin approval';
    END IF;
  ELSE
    IF v_task.status <> 'ready_for_completion'::public.task_status THEN
      RAISE EXCEPTION 'Task is not ready for admin approval';
    END IF;
  END IF;

  UPDATE public.tasks
  SET status='completed'::public.task_status,
      manager_confirmed=TRUE,
      manager_confirmed_by=auth.uid(),
      manager_confirmed_at=NOW(),
      completed_at=NOW(),
      completed_by=auth.uid(),
      updated_at=NOW()
  WHERE id=p_task_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_task(UUID) TO authenticated;

/* Keep the old RPC name available for compatibility, but route it
   through the new GM-only approval action. */
CREATE OR REPLACE FUNCTION public.confirm_task(p_task_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM public.approve_task(p_task_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.confirm_task(UUID) TO authenticated;

/* ================================================================
   5) Reopen clears review/approval state
   ================================================================ */
CREATE OR REPLACE FUNCTION public.reopen_task(p_task_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
BEGIN
  IF NOT (private.is_gm() OR COALESCE((SELECT enabled FROM public.user_permissions
      WHERE user_id=auth.uid() AND permission_key='tasks.reopen'),FALSE)) THEN
    RAISE EXCEPTION 'Reopen task permission required';
  END IF;

  UPDATE public.tasks
  SET status='in_progress'::public.task_status,
      manager_confirmed=FALSE,
      manager_confirmed_by=NULL,
      manager_confirmed_at=NULL,
      follower_reviewed_at=NULL,
      follower_reviewed_by=NULL,
      updated_at=NOW(),
      reopened_at=NOW(),
      reopened_by=auth.uid()
  WHERE id=p_task_id
    AND deleted_at IS NULL
    AND status='completed'::public.task_status;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Task not found or not completed';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reopen_task(UUID) TO authenticated;

/* ================================================================
   6) Notifications for the new workflow step
   ================================================================ */
CREATE OR REPLACE FUNCTION public.notify_task_status(
  p_task_id UUID,
  p_status TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  t public.tasks%ROWTYPE;
  u UUID;
  lang TEXT;
  v_title TEXT;
  v_body TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT * INTO t FROM public.tasks WHERE id=p_task_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Task not found';
  END IF;

  IF NOT (private.is_manager()
      OR t.created_by=auth.uid()
      OR t.responsible_id=auth.uid()
      OR t.follower_id=auth.uid()
      OR private.is_gm()) THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  /* Standard status notification to task participants. */
  FOREACH u IN ARRAY ARRAY[t.responsible_id,t.follower_id,t.created_by]::UUID[] LOOP
    IF u IS NOT NULL AND u <> auth.uid()
       AND NOT (p_status='ready_for_completion' AND t.follower_id=u) THEN
      SELECT COALESCE(preferred_language,'ar') INTO lang
      FROM public.profiles WHERE id=u;

      IF lower(COALESCE(lang,'ar'))='en' THEN
        v_title := CASE p_status
          WHEN 'awaiting_approval' THEN 'Admin approval required'
          WHEN 'completed' THEN 'Task Completed'
          WHEN 'ready_for_completion' THEN 'Task Ready for Completion'
          ELSE 'Task Status Updated'
        END;
      ELSE
        v_title := CASE p_status
          WHEN 'awaiting_approval' THEN 'مطلوب اعتماد العملية'
          WHEN 'completed' THEN 'اكتملت المهمة'
          WHEN 'ready_for_completion' THEN 'المهمة جاهزة للإنجاز'
          ELSE 'تم تحديث حالة المهمة'
        END;
      END IF;

      INSERT INTO public.notifications(user_id,type,title,body,target_type,target_id,dedupe_key,actor_id)
      VALUES(
        u,
        'task_status',
        v_title,
        t.title,
        'task',t.id,
        'task_status:'||t.id::TEXT||':'||p_status||':'||u::TEXT,
        auth.uid()
      ) ON CONFLICT (dedupe_key) DO NOTHING;
    END IF;
  END LOOP;

  /* Responsible requests completion -> follower reviews. */
  IF p_status='ready_for_completion' AND t.follower_id IS NOT NULL AND t.follower_id <> auth.uid() THEN
    SELECT COALESCE(preferred_language,'ar') INTO lang
    FROM public.profiles WHERE id=t.follower_id;

    INSERT INTO public.notifications(user_id,type,title,body,target_type,target_id,dedupe_key,actor_id)
    VALUES(
      t.follower_id,
      'task_review_required',
      CASE WHEN lower(COALESCE(lang,'ar'))='en' THEN 'Task review required' ELSE 'مطلوب مراجعة المهمة' END,
      CASE WHEN lower(COALESCE(lang,'ar'))='en'
        THEN 'The responsible person requested completion. Please review the task and mark Follow-up completed.'
        ELSE 'المسؤول طلب إكمال المهمة. يرجى مراجعة المهمة ثم الضغط على «تمت المتابعة».' END,
      'task',t.id,
      'task_review_required:'||t.id::TEXT||':'||t.follower_id::TEXT||':'||COALESCE(extract(epoch from t.completion_requested_at)::bigint,0)::TEXT,
      auth.uid()
    ) ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;

  /* Follower review -> General Manager approves. */
  IF p_status='awaiting_approval' THEN
    INSERT INTO public.notifications(user_id,type,title,body,target_type,target_id,dedupe_key,actor_id)
    SELECT p.id,
           'task_approval_required',
           CASE WHEN lower(COALESCE(p.preferred_language,'ar'))='en' THEN 'Admin approval required' ELSE 'مطلوب اعتماد العملية' END,
           CASE WHEN lower(COALESCE(p.preferred_language,'ar'))='en'
             THEN 'The task was reviewed by the follower and is waiting for your approval.'
             ELSE 'تمت متابعة المهمة وهي الآن في انتظار اعتماد المدير العام.' END,
           'task',t.id,
           'task_approval_required:'||t.id::TEXT||':'||p.id::TEXT||':'||COALESCE(extract(epoch from t.follower_reviewed_at)::bigint,0)::TEXT,
           auth.uid()
    FROM public.profiles p
    WHERE p.is_active=TRUE
      AND p.role='gm'
      AND p.id<>auth.uid()
    ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_task_status(UUID,TEXT) TO authenticated;

COMMIT;

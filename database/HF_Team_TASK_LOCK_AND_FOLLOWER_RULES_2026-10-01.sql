-- HF Team: task locking + follower write boundaries
-- 1) Completed tasks become read-only for all task activity.
-- 2) Follower may write only Daily Work Log and Task Chat while task is open.
-- 3) Follower can view Progress and Stages but cannot add/edit them.
-- 4) Responsible/manager/GM retain execution/progress rights according to existing permissions.

BEGIN;

/* ================================================================
   1) Task stages: no mutations after completion.
      Follower has SELECT only.
   ================================================================ */
ALTER TABLE public.task_stages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_stages_insert ON public.task_stages;
CREATE POLICY task_stages_insert ON public.task_stages
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND EXISTS (
    SELECT 1
    FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status <> 'completed'::public.task_status
      AND (
        private.is_gm()
        OR private.is_manager()
        OR t.created_by = auth.uid()
      )
  )
);

DROP POLICY IF EXISTS task_stages_update ON public.task_stages;
CREATE POLICY task_stages_update ON public.task_stages
FOR UPDATE TO authenticated
USING (
  (private.is_gm() OR private.is_manager() OR created_by = auth.uid())
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status <> 'completed'::public.task_status
  )
)
WITH CHECK (
  (private.is_gm() OR private.is_manager() OR created_by = auth.uid())
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status <> 'completed'::public.task_status
  )
);

DROP POLICY IF EXISTS task_stages_delete ON public.task_stages;
CREATE POLICY task_stages_delete ON public.task_stages
FOR DELETE TO authenticated
USING (
  (private.is_gm() OR private.is_manager() OR created_by = auth.uid())
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status <> 'completed'::public.task_status
  )
);

/* ================================================================
   2) Daily Work Log / progress.
      Follower can INSERT while in progress, but cannot edit/delete
      other users' entries. Completed task = completely locked.
   ================================================================ */
ALTER TABLE public.task_daily_updates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_daily_updates_insert ON public.task_daily_updates;
CREATE POLICY task_daily_updates_insert ON public.task_daily_updates
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status = 'in_progress'::public.task_status
      AND (
        private.is_gm()
        OR private.is_manager()
        OR t.responsible_id = auth.uid()
        OR t.follower_id = auth.uid()
      )
  )
);

DROP POLICY IF EXISTS task_daily_updates_update ON public.task_daily_updates;
CREATE POLICY task_daily_updates_update ON public.task_daily_updates
FOR UPDATE TO authenticated
USING (
  (created_by = auth.uid() OR private.is_gm() OR private.is_manager())
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status <> 'completed'::public.task_status
  )
)
WITH CHECK (
  (created_by = auth.uid() OR private.is_gm() OR private.is_manager())
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status <> 'completed'::public.task_status
  )
);

DROP POLICY IF EXISTS task_daily_updates_delete ON public.task_daily_updates;
CREATE POLICY task_daily_updates_delete ON public.task_daily_updates
FOR DELETE TO authenticated
USING (
  (created_by = auth.uid() OR private.is_gm() OR private.is_manager())
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status <> 'completed'::public.task_status
  )
);

/* ================================================================
   3) Task Chat.
      Follower + responsible + manager/GM may chat while task is open.
      Completed task = read-only.
   ================================================================ */
ALTER TABLE public.task_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_comments_select ON public.task_comments;
CREATE POLICY task_comments_select ON public.task_comments
FOR SELECT TO authenticated
USING (private.can_access_task(task_id));

DROP POLICY IF EXISTS task_comments_insert ON public.task_comments;
CREATE POLICY task_comments_insert ON public.task_comments
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status <> 'completed'::public.task_status
      AND (
        private.is_gm()
        OR private.is_manager()
        OR t.responsible_id = auth.uid()
        OR t.follower_id = auth.uid()
      )
  )
);

DROP POLICY IF EXISTS task_comments_update ON public.task_comments;
CREATE POLICY task_comments_update ON public.task_comments
FOR UPDATE TO authenticated
USING (
  created_by = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status <> 'completed'::public.task_status
  )
)
WITH CHECK (
  created_by = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status <> 'completed'::public.task_status
  )
);

DROP POLICY IF EXISTS task_comments_delete ON public.task_comments;
CREATE POLICY task_comments_delete ON public.task_comments
FOR DELETE TO authenticated
USING (
  (created_by = auth.uid() OR private.is_gm() OR private.is_manager())
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status <> 'completed'::public.task_status
  )
);

/* ================================================================
   4) Attachments.
      Direct task attachments are not available to the follower.
      Daily-log/chat attachments remain available while the task is open.
   ================================================================ */
DROP POLICY IF EXISTS attachments_insert ON public.attachments;
CREATE POLICY attachments_insert ON public.attachments
FOR INSERT TO authenticated
WITH CHECK (
  uploaded_by = auth.uid()
  AND (
    /* Direct task attachment: follower cannot write here. */
    (
      task_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.tasks t
        WHERE t.id = task_id
          AND t.deleted_at IS NULL
          AND t.status <> 'completed'::public.task_status
          AND (
            private.is_gm()
            OR private.is_manager()
            OR t.responsible_id = auth.uid()
          )
      )
    )
    OR
    /* Daily work attachment: follower is allowed while task is open. */
    (
      daily_update_id IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.task_daily_updates d
        JOIN public.tasks t ON t.id = d.task_id
        WHERE d.id = daily_update_id
          AND t.deleted_at IS NULL
          AND t.status = 'in_progress'::public.task_status
          AND (
            private.is_gm()
            OR private.is_manager()
            OR t.responsible_id = auth.uid()
            OR t.follower_id = auth.uid()
          )
      )
    )
    OR
    /* Task chat attachment: follower is allowed while task is open. */
    (
      task_comment_id IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.task_comments c
        JOIN public.tasks t ON t.id = c.task_id
        WHERE c.id = task_comment_id
          AND t.deleted_at IS NULL
          AND t.status <> 'completed'::public.task_status
          AND (
            private.is_gm()
            OR private.is_manager()
            OR t.responsible_id = auth.uid()
            OR t.follower_id = auth.uid()
          )
      )
    )
    OR
    /* Keep existing message attachments working. */
    (
      message_id IS NOT NULL
      AND private.can_access_message(message_id)
    )
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

/* ================================================================
   5) Follower notes also become read-only after completion.
   ================================================================ */
DROP POLICY IF EXISTS task_follower_notes_insert ON public.task_follower_notes;
CREATE POLICY task_follower_notes_insert ON public.task_follower_notes
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status <> 'completed'::public.task_status
      AND (
        t.follower_id = auth.uid()
        OR private.is_gm()
        OR private.is_manager()
      )
  )
);

DROP POLICY IF EXISTS task_follower_notes_update ON public.task_follower_notes;
CREATE POLICY task_follower_notes_update ON public.task_follower_notes
FOR UPDATE TO authenticated
USING (
  (created_by = auth.uid() OR private.is_gm() OR private.is_manager())
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status <> 'completed'::public.task_status
  )
)
WITH CHECK (
  (created_by = auth.uid() OR private.is_gm() OR private.is_manager())
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status <> 'completed'::public.task_status
  )
);

DROP POLICY IF EXISTS task_follower_notes_delete ON public.task_follower_notes;
CREATE POLICY task_follower_notes_delete ON public.task_follower_notes
FOR DELETE TO authenticated
USING (
  (created_by = auth.uid() OR private.is_gm() OR private.is_manager())
  AND EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_id
      AND t.deleted_at IS NULL
      AND t.status <> 'completed'::public.task_status
  )
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.task_comments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.task_stages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.task_daily_updates TO authenticated;

COMMIT;

-- Hama Work - Phase 2/3 Fix Pack
-- Scope:
-- 1) Follower notes
-- 2) Per-user notification language (AR/EN)
-- 3) Safe Egypt timezone helper
-- 4) Daily work log schema compatibility (quantity optional where supported)
--
-- Run this AFTER Hama_Work_3_MODULES_FINAL.sql and the existing
-- task_follower_notes patch.

BEGIN;

-- ============================================================
-- 1) FOLLOWER NOTES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.task_follower_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  note TEXT NOT NULL CHECK (length(trim(note)) > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS task_follower_notes_task_idx
  ON public.task_follower_notes(task_id, created_at);

CREATE INDEX IF NOT EXISTS task_follower_notes_user_idx
  ON public.task_follower_notes(created_by, created_at);

CREATE OR REPLACE FUNCTION public.set_task_follower_note_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS task_follower_notes_set_updated_at
ON public.task_follower_notes;

CREATE TRIGGER task_follower_notes_set_updated_at
BEFORE UPDATE ON public.task_follower_notes
FOR EACH ROW
EXECUTE FUNCTION public.set_task_follower_note_updated_at();

ALTER TABLE public.task_follower_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_follower_notes_select ON public.task_follower_notes;
CREATE POLICY task_follower_notes_select
ON public.task_follower_notes
FOR SELECT TO authenticated
USING (private.can_access_task(task_id));

DROP POLICY IF EXISTS task_follower_notes_insert ON public.task_follower_notes;
CREATE POLICY task_follower_notes_insert
ON public.task_follower_notes
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND EXISTS (
    SELECT 1
    FROM public.tasks t
    WHERE t.id = task_id
      AND (
        t.follower_id = auth.uid()
        OR private.is_gm()
        OR private.is_manager()
      )
  )
);

DROP POLICY IF EXISTS task_follower_notes_update ON public.task_follower_notes;
CREATE POLICY task_follower_notes_update
ON public.task_follower_notes
FOR UPDATE TO authenticated
USING (
  created_by = auth.uid()
  OR private.is_gm()
  OR private.is_manager()
)
WITH CHECK (
  created_by = auth.uid()
  OR private.is_gm()
  OR private.is_manager()
);

DROP POLICY IF EXISTS task_follower_notes_delete ON public.task_follower_notes;
CREATE POLICY task_follower_notes_delete
ON public.task_follower_notes
FOR DELETE TO authenticated
USING (
  created_by = auth.uid()
  OR private.is_gm()
  OR private.is_manager()
);

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.task_follower_notes TO authenticated;


-- ============================================================
-- 2) NOTIFICATION LANGUAGE
--    Notification title is generated from recipient language.
--    Message/task body remains the actual business content.
-- ============================================================

CREATE OR REPLACE FUNCTION private.notification_title(
  p_type TEXT,
  p_status TEXT DEFAULT NULL,
  p_language TEXT DEFAULT 'ar'
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF lower(coalesce(p_language, 'ar')) = 'en' THEN
    RETURN CASE
      WHEN p_type = 'task_created' THEN 'New Task'
      WHEN p_type = 'task_ready' THEN 'Task Ready for Completion'
      WHEN p_type = 'task_status' AND p_status = 'completed' THEN 'Task Completed'
      WHEN p_type = 'task_status' AND p_status = 'cancelled' THEN 'Task Cancelled'
      WHEN p_type = 'task_status' THEN 'Task Status Updated'
      WHEN p_type = 'message' THEN 'New Message'
      WHEN p_type = 'deadline' THEN 'Task Deadline Approaching'
      WHEN p_type = 'overdue' THEN 'Task Overdue'
      ELSE 'New Notification'
    END;
  END IF;

  RETURN CASE
    WHEN p_type = 'task_created' THEN 'مهمة جديدة'
    WHEN p_type = 'task_ready' THEN 'المهمة جاهزة للمراجعة'
    WHEN p_type = 'task_status' AND p_status = 'completed' THEN 'تم إكمال المهمة'
    WHEN p_type = 'task_status' AND p_status = 'cancelled' THEN 'تم إلغاء المهمة'
    WHEN p_type = 'task_status' THEN 'تم تحديث حالة المهمة'
    WHEN p_type = 'message' THEN 'رسالة جديدة'
    WHEN p_type = 'deadline' THEN 'موعد استحقاق المهمة يقترب'
    WHEN p_type = 'overdue' THEN 'المهمة متأخرة'
    ELSE 'تنبيه جديد'
  END;
END;
$$;


CREATE OR REPLACE FUNCTION public.notify_task_created(p_task_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  t public.tasks%ROWTYPE;
  u UUID;
  lang TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  SELECT * INTO t FROM public.tasks WHERE id = p_task_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found'; END IF;

  IF NOT (t.created_by = auth.uid() OR private.is_manager()) THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  FOREACH u IN ARRAY ARRAY[t.responsible_id, t.follower_id]::UUID[] LOOP
    IF u IS NOT NULL AND u <> t.created_by THEN
      SELECT COALESCE(preferred_language, 'ar')
        INTO lang
      FROM public.profiles
      WHERE id = u;

      INSERT INTO public.notifications(
        user_id, type, title, body, target_type, target_id, dedupe_key
      )
      VALUES(
        u,
        'task_created',
        private.notification_title('task_created', NULL, lang),
        t.title,
        'task',
        t.id,
        'task_created:' || t.id::TEXT || ':' || u::TEXT
      )
      ON CONFLICT (dedupe_key) DO NOTHING;
    END IF;
  END LOOP;
END;
$$;


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
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  SELECT * INTO t FROM public.tasks WHERE id = p_task_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found'; END IF;

  IF NOT (
    private.is_manager()
    OR t.created_by = auth.uid()
    OR t.responsible_id = auth.uid()
    OR t.follower_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  FOREACH u IN ARRAY ARRAY[
    t.responsible_id,
    t.follower_id,
    t.created_by
  ]::UUID[] LOOP

    IF u IS NOT NULL AND u <> auth.uid() THEN
      SELECT COALESCE(preferred_language, 'ar')
        INTO lang
      FROM public.profiles
      WHERE id = u;

      INSERT INTO public.notifications(
        user_id, type, title, body, target_type, target_id, dedupe_key
      )
      VALUES(
        u,
        'task_status',
        private.notification_title('task_status', p_status, lang),
        t.title,
        'task',
        t.id,
        'task_status:' || t.id::TEXT || ':' || p_status || ':' || u::TEXT
      )
      ON CONFLICT (dedupe_key) DO NOTHING;
    END IF;
  END LOOP;

  IF p_status = 'ready_for_completion' THEN
    INSERT INTO public.notifications(
      user_id, type, title, body, target_type, target_id, dedupe_key
    )
    SELECT
      p.id,
      'task_ready',
      private.notification_title(
        'task_ready',
        NULL,
        COALESCE(p.preferred_language, 'ar')
      ),
      t.title,
      'task',
      t.id,
      'task_ready:' || t.id::TEXT || ':' || p.id::TEXT
    FROM public.profiles p
    WHERE p.is_active = TRUE
      AND p.role IN ('gm','manager')
      AND p.id <> auth.uid()
    ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;
END;
$$;


CREATE OR REPLACE FUNCTION private.notify_message_recipient()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_message public.messages%ROWTYPE;
  v_language TEXT;
BEGIN
  SELECT * INTO v_message
  FROM public.messages
  WHERE id = NEW.message_id;

  SELECT COALESCE(preferred_language, 'ar')
    INTO v_language
  FROM public.profiles
  WHERE id = NEW.user_id;

  INSERT INTO public.notifications(
    user_id, type, title, body, target_type, target_id, dedupe_key
  )
  VALUES(
    NEW.user_id,
    'message',
    private.notification_title('message', NULL, v_language),
    v_message.content,
    'message',
    v_message.id,
    'message:' || v_message.id::TEXT || ':' || NEW.user_id::TEXT
  )
  ON CONFLICT (dedupe_key) DO NOTHING;

  RETURN NEW;
END;
$$;


CREATE OR REPLACE FUNCTION public.notify_message_sent(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  m public.messages%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  SELECT * INTO m
  FROM public.messages
  WHERE id = p_message_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Message not found'; END IF;

  IF NOT (m.created_by = auth.uid() OR private.is_manager()) THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  INSERT INTO public.notifications(
    user_id, type, title, body, target_type, target_id, dedupe_key
  )
  SELECT
    r.user_id,
    'message',
    private.notification_title(
      'message',
      NULL,
      COALESCE(p.preferred_language, 'ar')
    ),
    m.content,
    'message',
    m.id,
    'message:' || m.id::TEXT || ':' || r.user_id::TEXT
  FROM public.message_recipients r
  JOIN public.profiles p ON p.id = r.user_id
  WHERE r.message_id = m.id
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$;


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

    IF t.deadline < NOW() AND t.status <> 'overdue' THEN
      UPDATE public.tasks
      SET status = 'overdue'
      WHERE id = t.id;
    END IF;

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

    IF t.deadline < NOW() AND t.status = 'overdue' THEN
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



-- ============================================================
-- 2B) REALTIME TASK TRIGGERS: localized titles
--     These triggers are the primary notification path, so they
--     must use the recipient's preferred language too.
-- ============================================================

CREATE OR REPLACE FUNCTION private.notify_task_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user UUID;
  v_language TEXT;
  v_actor_name TEXT;
  v_action_en TEXT;
  v_action_ar TEXT;
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN RETURN NEW; END IF;

  SELECT COALESCE(p.full_name, 'User')
    INTO v_actor_name
  FROM public.profiles p
  WHERE p.id = auth.uid();

  IF TG_OP = 'INSERT' THEN
    FOREACH v_user IN ARRAY ARRAY[
      NEW.responsible_id,
      NEW.follower_id
    ]::UUID[] LOOP

      IF v_user IS NOT NULL AND v_user <> NEW.created_by THEN
        SELECT COALESCE(preferred_language, 'ar')
          INTO v_language
        FROM public.profiles
        WHERE id = v_user;

        INSERT INTO public.notifications(
          user_id, type, title, body,
          target_type, target_id, dedupe_key, actor_id
        )
        VALUES(
          v_user,
          'task_created',
          private.notification_title('task_created', NULL, v_language),
          CASE
            WHEN COALESCE(v_language,'ar') = 'en'
              THEN COALESCE(v_actor_name,'System') || ' created the task: ' || NEW.title
            ELSE COALESCE(v_actor_name,'النظام') || ' أنشأ المهمة: ' || NEW.title
          END,
          'task',
          NEW.id,
          'task_created:' || NEW.id::TEXT || ':' || v_user::TEXT,
          auth.uid()
        )
        ON CONFLICT (dedupe_key) DO NOTHING;
      END IF;
    END LOOP;

  ELSIF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN

    v_action_en := CASE NEW.status::TEXT
      WHEN 'in_progress' THEN 'started the task'
      WHEN 'ready_for_completion' THEN 'requested completion for the task'
      WHEN 'completed' THEN 'completed the task'
      WHEN 'cancelled' THEN 'cancelled the task'
      WHEN 'not_started' THEN 'returned the task to Not Started'
      ELSE 'changed the task status to ' || NEW.status::TEXT
    END;

    v_action_ar := CASE NEW.status::TEXT
      WHEN 'in_progress' THEN 'بدأ تنفيذ المهمة'
      WHEN 'ready_for_completion' THEN 'طلب إنهاء المهمة'
      WHEN 'completed' THEN 'أكمل المهمة'
      WHEN 'cancelled' THEN 'ألغى المهمة'
      WHEN 'not_started' THEN 'أعاد المهمة إلى حالة لم تبدأ'
      ELSE 'غيّر حالة المهمة إلى ' || NEW.status::TEXT
    END;

    FOREACH v_user IN ARRAY ARRAY[
      NEW.responsible_id,
      NEW.follower_id,
      NEW.created_by
    ]::UUID[] LOOP

      IF v_user IS NOT NULL AND v_user <> auth.uid() THEN
        SELECT COALESCE(preferred_language, 'ar')
          INTO v_language
        FROM public.profiles
        WHERE id = v_user;

        INSERT INTO public.notifications(
          user_id, type, title, body,
          target_type, target_id, dedupe_key, actor_id
        )
        VALUES(
          v_user,
          'task_status',
          private.notification_title('task_status', NEW.status::TEXT, v_language),
          CASE
            WHEN COALESCE(v_language,'ar') = 'en'
              THEN COALESCE(v_actor_name,'System') || ' ' || v_action_en || ': ' || NEW.title
            ELSE COALESCE(v_actor_name,'النظام') || ' ' || v_action_ar || ': ' || NEW.title
          END,
          'task',
          NEW.id,
          'task_status:' || NEW.id::TEXT || ':' || NEW.status::TEXT || ':' || v_user::TEXT,
          auth.uid()
        )
        ON CONFLICT (dedupe_key) DO NOTHING;
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;


CREATE OR REPLACE FUNCTION private.notify_daily_task_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  t public.tasks%ROWTYPE;
  u UUID;
  v_language TEXT;
  v_actor_name TEXT;
  v_qty TEXT;
BEGIN
  SELECT * INTO t FROM public.tasks WHERE id = NEW.task_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  SELECT COALESCE(p.full_name,'User')
    INTO v_actor_name
  FROM public.profiles p
  WHERE p.id = NEW.created_by;

  v_qty := CASE
    WHEN NEW.quantity_done IS NULL THEN
      ''
    ELSE
      trim(to_char(NEW.quantity_done, 'FM999999990.##')) || ' ' ||
      COALESCE(t.quantity_unit, 'units')
  END;

  FOREACH u IN ARRAY ARRAY[
    t.created_by,
    t.responsible_id,
    t.follower_id
  ]::UUID[] LOOP

    IF u IS NOT NULL AND u <> NEW.created_by THEN
      SELECT COALESCE(preferred_language,'ar')
        INTO v_language
      FROM public.profiles
      WHERE id = u;

      INSERT INTO public.notifications(
        user_id,type,title,body,target_type,target_id,dedupe_key,actor_id
      )
      VALUES(
        u,
        'daily_progress',
        CASE
          WHEN v_language = 'en' THEN 'Daily Progress'
          ELSE 'التقدم اليومي'
        END,
        CASE
          WHEN v_language = 'en' THEN
            CASE WHEN v_qty = ''
              THEN v_actor_name || ' added a daily work record for: ' || t.title
              ELSE v_actor_name || ' recorded ' || v_qty || ' on: ' || t.title
            END
          ELSE
            CASE WHEN v_qty = ''
              THEN v_actor_name || ' أضاف سجل عمل يومي للمهمة: ' || t.title
              ELSE v_actor_name || ' سجّل ' || v_qty || ' في المهمة: ' || t.title
            END
        END,
        'task',
        t.id,
        'daily_progress:' || NEW.id::TEXT || ':' || u::TEXT,
        NEW.created_by
      )
      ON CONFLICT (dedupe_key) DO NOTHING;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

-- Enable Realtime for follower notes when the publication exists.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) THEN
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.task_follower_notes;
    EXCEPTION WHEN duplicate_object THEN
      NULL;
    END;
  END IF;
END
$$;

-- ============================================================
-- 3) EGYPT TIMEZONE
-- ============================================================
-- PostgreSQL TIMESTAMPTZ should remain UTC internally.
-- The UI must render with DateTime.toLocal()/a Cairo timezone package.
-- This function is provided for DB-side reports/RPCs that need Egypt time.

CREATE OR REPLACE FUNCTION public.egypt_local_timestamp(p_ts TIMESTAMPTZ)
RETURNS TIMESTAMP
LANGUAGE sql
STABLE
AS $$
  SELECT p_ts AT TIME ZONE 'Africa/Cairo';
$$;


-- ============================================================
-- 4) DAILY WORK LOG: quantity is optional
-- ============================================================
-- Do this only if the current table/column exists.
-- We deliberately do not rename or recreate the application's table.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'task_daily_updates'
      AND column_name = 'quantity_done'
  ) THEN
    EXECUTE '
      ALTER TABLE public.task_daily_updates
      ALTER COLUMN quantity_done DROP NOT NULL
    ';
  END IF;
END
$$;


-- ============================================================
-- 5) GRANTS
-- ============================================================

GRANT EXECUTE ON FUNCTION private.notification_title(TEXT,TEXT,TEXT)
TO authenticated;

GRANT EXECUTE ON FUNCTION public.egypt_local_timestamp(TIMESTAMPTZ)
TO authenticated;

GRANT EXECUTE ON FUNCTION public.notify_task_created(UUID)
TO authenticated;

GRANT EXECUTE ON FUNCTION public.notify_task_status(UUID,TEXT)
TO authenticated;

GRANT EXECUTE ON FUNCTION public.notify_message_sent(UUID)
TO authenticated;

COMMIT;


-- ============================================================
-- Verification
-- ============================================================

SELECT
  'task_follower_notes' AS object_name,
  to_regclass('public.task_follower_notes') IS NOT NULL AS exists;

SELECT
  column_name,
  is_nullable,
  data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'task_daily_updates'
  AND column_name = 'quantity_done';

SELECT
  routine_schema,
  routine_name
FROM information_schema.routines
WHERE routine_schema IN ('public','private')
  AND routine_name IN (
    'notification_title',
    'egypt_local_timestamp',
    'notify_task_created',
    'notify_task_status',
    'notify_message_sent',
    'sync_task_due_notifications'
  )
ORDER BY routine_schema, routine_name;
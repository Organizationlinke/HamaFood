-- Hama Work FINAL FIX - 2026-09-30
-- Fixes:
-- 1) Notification body language per recipient (Arabic/English)
-- 2) Daily achievement can be recorded more than once on the same day
-- 3) Daily achievement quantity is optional
-- Run AFTER the existing Hama Work database patches.

BEGIN;

/* ================================================================
   1. DAILY WORK LOG / ACHIEVEMENTS
   ================================================================ */

-- The old migration created a unique index that allowed only one
-- achievement row per task/stage/day/user. The application now supports
-- multiple entries on the same day, so that index must not exist.
DROP INDEX IF EXISTS public.task_daily_updates_unique_day;

-- Quantity is optional. NULL means the user recorded a note/attachment
-- without a numeric quantity.
ALTER TABLE public.task_daily_updates
  ALTER COLUMN quantity_done DROP NOT NULL;

/* ================================================================
   2. LOCALIZED TASK NOTIFICATIONS
   ================================================================ */

CREATE OR REPLACE FUNCTION private.notify_task_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user UUID;
  v_actor_name TEXT;
  v_lang TEXT;
  v_body TEXT;
  v_title TEXT;
  v_action_ar TEXT;
  v_action_en TEXT;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(p.full_name, 'User')
    INTO v_actor_name
  FROM public.profiles p
  WHERE p.id = COALESCE(auth.uid(), NEW.created_by);

  v_actor_name := COALESCE(v_actor_name, 'User');

  IF TG_OP = 'INSERT' THEN
    FOREACH v_user IN ARRAY ARRAY[NEW.responsible_id, NEW.follower_id]::UUID[] LOOP
      IF v_user IS NOT NULL AND v_user <> NEW.created_by THEN
        SELECT CASE WHEN lower(COALESCE(p.preferred_language, 'ar')) = 'en' THEN 'en' ELSE 'ar' END
          INTO v_lang
        FROM public.profiles p
        WHERE p.id = v_user;
        v_lang := COALESCE(v_lang, 'ar');

        IF v_lang = 'en' THEN
          v_title := 'New Task';
          v_body := v_actor_name || ' created the task: ' || NEW.title;
        ELSE
          v_title := 'مهمة جديدة';
          v_body := v_actor_name || ' أنشأ المهمة: ' || NEW.title;
        END IF;

        INSERT INTO public.notifications(
          user_id,type,title,body,target_type,target_id,dedupe_key,actor_id
        ) VALUES(
          v_user,'task_created',v_title,v_body,'task',NEW.id,
          'task_created:' || NEW.id::TEXT || ':' || v_user::TEXT,
          COALESCE(auth.uid(), NEW.created_by)
        )
        ON CONFLICT (dedupe_key) DO NOTHING;
      END IF;
    END LOOP;

  ELSIF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    FOREACH v_user IN ARRAY ARRAY[NEW.responsible_id, NEW.follower_id, NEW.created_by]::UUID[] LOOP
      IF v_user IS NOT NULL AND v_user <> auth.uid() THEN
        SELECT CASE WHEN lower(COALESCE(p.preferred_language, 'ar')) = 'en' THEN 'en' ELSE 'ar' END
          INTO v_lang
        FROM public.profiles p
        WHERE p.id = v_user;
        v_lang := COALESCE(v_lang, 'ar');

        IF v_lang = 'en' THEN
          v_title := CASE NEW.status::TEXT
            WHEN 'ready_for_completion' THEN 'Task Ready for Completion'
            WHEN 'completed' THEN 'Task Completed'
            WHEN 'cancelled' THEN 'Task Cancelled'
            ELSE 'Task Update'
          END;

          v_body := CASE NEW.status::TEXT
            WHEN 'in_progress' THEN v_actor_name || ' started the task: ' || NEW.title
            WHEN 'ready_for_completion' THEN v_actor_name || ' requested completion for the task: ' || NEW.title
            WHEN 'completed' THEN v_actor_name || ' completed the task: ' || NEW.title
            WHEN 'cancelled' THEN v_actor_name || ' cancelled the task: ' || NEW.title
            WHEN 'not_started' THEN v_actor_name || ' returned the task to Not Started: ' || NEW.title
            ELSE v_actor_name || ' changed the task status to ' || NEW.status::TEXT || ': ' || NEW.title
          END;
        ELSE
          v_title := CASE NEW.status::TEXT
            WHEN 'ready_for_completion' THEN 'المهمة جاهزة للإنجاز'
            WHEN 'completed' THEN 'اكتملت المهمة'
            WHEN 'cancelled' THEN 'تم إلغاء المهمة'
            ELSE 'تحديث المهمة'
          END;

          v_body := CASE NEW.status::TEXT
            WHEN 'in_progress' THEN v_actor_name || ' بدأ المهمة: ' || NEW.title
            WHEN 'ready_for_completion' THEN v_actor_name || ' طلب إتمام المهمة: ' || NEW.title
            WHEN 'completed' THEN v_actor_name || ' أكمل المهمة: ' || NEW.title
            WHEN 'cancelled' THEN v_actor_name || ' ألغى المهمة: ' || NEW.title
            WHEN 'not_started' THEN v_actor_name || ' أعاد المهمة إلى "لم تبدأ": ' || NEW.title
            ELSE v_actor_name || ' غيّر حالة المهمة إلى ' || NEW.status::TEXT || ': ' || NEW.title
          END;
        END IF;

        INSERT INTO public.notifications(
          user_id,type,title,body,target_type,target_id,dedupe_key,actor_id
        ) VALUES(
          v_user,'task_status',v_title,v_body,'task',NEW.id,
          'task_status:' || NEW.id::TEXT || ':' || NEW.status::TEXT || ':' || v_user::TEXT,
          COALESCE(auth.uid(), NEW.created_by)
        )
        ON CONFLICT (dedupe_key) DO NOTHING;
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

/* ================================================================
   3. LOCALIZED DAILY ACHIEVEMENT NOTIFICATIONS
   ================================================================ */

CREATE OR REPLACE FUNCTION private.notify_daily_task_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  t public.tasks%ROWTYPE;
  u UUID;
  v_actor_name TEXT;
  v_lang TEXT;
  v_body TEXT;
  v_qty TEXT;
  v_unit TEXT;
BEGIN
  SELECT * INTO t
  FROM public.tasks
  WHERE id = NEW.task_id;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(p.full_name, 'User')
    INTO v_actor_name
  FROM public.profiles p
  WHERE p.id = NEW.created_by;

  v_actor_name := COALESCE(v_actor_name, 'User');

  IF NEW.quantity_done IS NULL THEN
    v_qty := NULL;
  ELSE
    v_qty := trim(to_char(NEW.quantity_done, 'FM999999990.##'));
  END IF;

  v_unit := COALESCE(t.quantity_unit, 'units');

  FOREACH u IN ARRAY ARRAY[t.created_by, t.responsible_id, t.follower_id]::UUID[] LOOP
    IF u IS NOT NULL AND u <> NEW.created_by THEN
      SELECT CASE WHEN lower(COALESCE(p.preferred_language, 'ar')) = 'en' THEN 'en' ELSE 'ar' END
        INTO v_lang
      FROM public.profiles p
      WHERE p.id = u;
      v_lang := COALESCE(v_lang, 'ar');

      IF v_lang = 'en' THEN
        IF v_qty IS NULL THEN
          v_body := v_actor_name || ' recorded a daily achievement on the task: ' || t.title;
        ELSE
          v_body := v_actor_name || ' recorded ' || v_qty || ' ' || v_unit || ' on the task: ' || t.title;
        END IF;
      ELSE
        IF v_qty IS NULL THEN
          v_body := v_actor_name || ' سجل إنجازًا يوميًا في المهمة: ' || t.title;
        ELSE
          v_body := v_actor_name || ' سجل إنجازًا قدره ' || v_qty || ' ' || v_unit || ' في المهمة: ' || t.title;
        END IF;
      END IF;

      INSERT INTO public.notifications(
        user_id,type,title,body,target_type,target_id,dedupe_key,actor_id
      ) VALUES(
        u,'daily_progress',
        CASE WHEN v_lang = 'en' THEN 'Daily Progress' ELSE 'الإنجاز اليومي' END,
        v_body,'task',t.id,
        'daily_progress:' || NEW.id::TEXT || ':' || u::TEXT,
        NEW.created_by
      )
      ON CONFLICT (dedupe_key) DO NOTHING;
    END IF;
  END LOOP;

  IF t.created_by <> NEW.created_by THEN
    FOR u IN
      SELECT p.id
      FROM public.profiles p
      WHERE p.is_active = TRUE
        AND p.role IN ('gm','manager')
        AND p.id <> NEW.created_by
        AND p.id <> ALL(ARRAY[t.created_by, t.responsible_id, t.follower_id]::UUID[])
    LOOP
      SELECT CASE WHEN lower(COALESCE(p.preferred_language, 'ar')) = 'en' THEN 'en' ELSE 'ar' END
        INTO v_lang
      FROM public.profiles p
      WHERE p.id = u;
      v_lang := COALESCE(v_lang, 'ar');

      IF v_lang = 'en' THEN
        IF v_qty IS NULL THEN
          v_body := v_actor_name || ' recorded a daily achievement on the task: ' || t.title;
        ELSE
          v_body := v_actor_name || ' recorded ' || v_qty || ' ' || v_unit || ' on the task: ' || t.title;
        END IF;
      ELSE
        IF v_qty IS NULL THEN
          v_body := v_actor_name || ' سجل إنجازًا يوميًا في المهمة: ' || t.title;
        ELSE
          v_body := v_actor_name || ' سجل إنجازًا قدره ' || v_qty || ' ' || v_unit || ' في المهمة: ' || t.title;
        END IF;
      END IF;

      INSERT INTO public.notifications(
        user_id,type,title,body,target_type,target_id,dedupe_key,actor_id
      ) VALUES(
        u,'daily_progress',
        CASE WHEN v_lang = 'en' THEN 'Daily Progress' ELSE 'الإنجاز اليومي' END,
        v_body,'task',t.id,
        'daily_progress:' || NEW.id::TEXT || ':manager:' || u::TEXT,
        NEW.created_by
      )
      ON CONFLICT (dedupe_key) DO NOTHING;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS task_daily_update_notify ON public.task_daily_updates;
CREATE TRIGGER task_daily_update_notify
AFTER INSERT OR UPDATE ON public.task_daily_updates
FOR EACH ROW EXECUTE FUNCTION private.notify_daily_task_update();

/* ================================================================
   4. ONE-TIME CLEANUP OF EXISTING ARABIC NOTIFICATIONS
   ================================================================ */

UPDATE public.notifications n
SET body = regexp_replace(n.body, '^(.*) created the task: (.*)$', '\1 أنشأ المهمة: \2')
FROM public.profiles p
WHERE p.id = n.user_id
  AND lower(COALESCE(p.preferred_language,'ar')) <> 'en'
  AND n.type = 'task_created'
  AND n.body ~ ' created the task: ';

UPDATE public.notifications n
SET body = regexp_replace(n.body, '^(.*) started the task: (.*)$', '\1 بدأ المهمة: \2')
FROM public.profiles p
WHERE p.id = n.user_id
  AND lower(COALESCE(p.preferred_language,'ar')) <> 'en'
  AND n.type = 'task_status'
  AND n.body ~ ' started the task: ';

UPDATE public.notifications n
SET body = regexp_replace(n.body, '^(.*) requested completion for the task: (.*)$', '\1 طلب إتمام المهمة: \2')
FROM public.profiles p
WHERE p.id = n.user_id
  AND lower(COALESCE(p.preferred_language,'ar')) <> 'en'
  AND n.type = 'task_status'
  AND n.body ~ ' requested completion for the task: ';

UPDATE public.notifications n
SET body = regexp_replace(n.body, '^(.*) completed the task: (.*)$', '\1 أكمل المهمة: \2')
FROM public.profiles p
WHERE p.id = n.user_id
  AND lower(COALESCE(p.preferred_language,'ar')) <> 'en'
  AND n.type = 'task_status'
  AND n.body ~ ' completed the task: ';

UPDATE public.notifications n
SET body = regexp_replace(n.body, '^(.*) cancelled the task: (.*)$', '\1 ألغى المهمة: \2')
FROM public.profiles p
WHERE p.id = n.user_id
  AND lower(COALESCE(p.preferred_language,'ar')) <> 'en'
  AND n.type = 'task_status'
  AND n.body ~ ' cancelled the task: ';

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Verification:
SELECT indexname
FROM pg_indexes
WHERE schemaname='public'
  AND tablename='task_daily_updates'
  AND indexname='task_daily_updates_unique_day';

SELECT column_name, is_nullable
FROM information_schema.columns
WHERE table_schema='public'
  AND table_name='task_daily_updates'
  AND column_name='quantity_done';

-- Hama Work - All Task/Message Activity Notifications + Fast Push
-- Run AFTER Hama_Work_FINAL_FIX_2026-09-30.sql
-- This patch is idempotent.

BEGIN;

/* ================================================================
   1) Common localized notification helper
   ================================================================ */

CREATE OR REPLACE FUNCTION private.insert_activity_notification(
  p_user_id UUID,
  p_actor_id UUID,
  p_type TEXT,
  p_title_ar TEXT,
  p_title_en TEXT,
  p_body_ar TEXT,
  p_body_en TEXT,
  p_target_type TEXT,
  p_target_id UUID,
  p_dedupe_key TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_lang TEXT;
  v_title TEXT;
  v_body TEXT;
BEGIN
  IF p_user_id IS NULL OR p_user_id = p_actor_id THEN
    RETURN;
  END IF;

  SELECT CASE
    WHEN lower(COALESCE(preferred_language, 'ar')) = 'en' THEN 'en'
    ELSE 'ar'
  END
  INTO v_lang
  FROM public.profiles
  WHERE id = p_user_id;

  v_lang := COALESCE(v_lang, 'ar');
  v_title := CASE WHEN v_lang = 'en' THEN p_title_en ELSE p_title_ar END;
  v_body  := CASE WHEN v_lang = 'en' THEN p_body_en  ELSE p_body_ar  END;

  INSERT INTO public.notifications(
    user_id, type, title, body, target_type, target_id, dedupe_key, actor_id
  )
  VALUES(
    p_user_id, p_type, v_title, v_body,
    p_target_type, p_target_id, p_dedupe_key, p_actor_id
  )
  ON CONFLICT (dedupe_key) DO NOTHING;
END;
$$;

/* ================================================================
   2) Task metadata/assignment changes
   ================================================================ */

CREATE OR REPLACE FUNCTION private.notify_task_metadata_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  actor UUID;
  actor_name TEXT;
  u UUID;
  action_ar TEXT;
  action_en TEXT;
BEGIN
  actor := COALESCE(auth.uid(), NEW.created_by);
  SELECT COALESCE(full_name, 'User') INTO actor_name
  FROM public.profiles WHERE id = actor;
  actor_name := COALESCE(actor_name, 'User');

  IF NEW.responsible_id IS DISTINCT FROM OLD.responsible_id
     OR NEW.follower_id IS DISTINCT FROM OLD.follower_id THEN
    action_ar := 'حدّث المسؤول أو المتابع للمهمة: ' || NEW.title;
    action_en := 'updated the task responsible person or follower: ' || NEW.title;
  ELSIF NEW.priority IS DISTINCT FROM OLD.priority THEN
    action_ar := 'غيّر أولوية المهمة: ' || NEW.title;
    action_en := 'changed the task priority: ' || NEW.title;
  ELSIF NEW.deadline IS DISTINCT FROM OLD.deadline THEN
    action_ar := 'غيّر الموعد النهائي للمهمة: ' || NEW.title;
    action_en := 'changed the task deadline: ' || NEW.title;
  ELSIF NEW.total_quantity IS DISTINCT FROM OLD.total_quantity
     OR NEW.quantity_unit IS DISTINCT FROM OLD.quantity_unit THEN
    action_ar := 'حدّث كمية/وحدة المهمة: ' || NEW.title;
    action_en := 'updated the task quantity/unit: ' || NEW.title;
  ELSIF NEW.manager_confirmed IS DISTINCT FROM OLD.manager_confirmed THEN
    action_ar := 'حدّث تأكيد المدير للمهمة: ' || NEW.title;
    action_en := 'updated manager confirmation for the task: ' || NEW.title;
  ELSIF NEW.score IS DISTINCT FROM OLD.score THEN
    action_ar := 'قيّم المهمة: ' || NEW.title;
    action_en := 'evaluated the task: ' || NEW.title;
  ELSE
    RETURN NEW;
  END IF;

  FOR u IN
    SELECT DISTINCT x.user_id
    FROM (VALUES (NEW.created_by), (NEW.responsible_id), (NEW.follower_id)) AS x(user_id)
    WHERE x.user_id IS NOT NULL
  LOOP
    PERFORM private.insert_activity_notification(
      u, actor, 'task_activity',
      'تحديث في المهمة', 'Task Activity',
      actor_name || ' ' || action_ar,
      actor_name || ' ' || action_en,
      'task', NEW.id,
      'task_activity:' || NEW.id::TEXT || ':' || extract(epoch from clock_timestamp())::bigint::TEXT || ':' || u::TEXT
    );
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tasks_metadata_activity_notify ON public.tasks;
CREATE TRIGGER tasks_metadata_activity_notify
AFTER UPDATE OF responsible_id, follower_id, priority, deadline, total_quantity, quantity_unit, manager_confirmed, score
ON public.tasks
FOR EACH ROW EXECUTE FUNCTION private.notify_task_metadata_activity();

/* ================================================================
   2) Task chat messages
   ================================================================ */

CREATE OR REPLACE FUNCTION private.notify_task_comment_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  t public.tasks%ROWTYPE;
  actor_name TEXT;
  u UUID;
BEGIN
  SELECT * INTO t FROM public.tasks WHERE id = NEW.task_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  SELECT COALESCE(full_name, 'User') INTO actor_name
  FROM public.profiles WHERE id = NEW.created_by;
  actor_name := COALESCE(actor_name, 'User');

  FOR u IN
    SELECT DISTINCT x.user_id
    FROM (
      VALUES (t.created_by), (t.responsible_id), (t.follower_id)
    ) AS x(user_id)
    WHERE x.user_id IS NOT NULL
  LOOP
    PERFORM private.insert_activity_notification(
      u, NEW.created_by, 'task_comment',
      'رسالة جديدة في المهمة', 'New Task Message',
      actor_name || ' أضاف ردًا في المهمة: ' || t.title,
      actor_name || ' added a reply to the task: ' || t.title,
      'task', t.id,
      'task_comment:' || NEW.id::TEXT || ':' || u::TEXT
    );
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS task_comments_activity_notify ON public.task_comments;
CREATE TRIGGER task_comments_activity_notify
AFTER INSERT ON public.task_comments
FOR EACH ROW EXECUTE FUNCTION private.notify_task_comment_activity();

/* ================================================================
   3) Follower notes
   ================================================================ */

CREATE OR REPLACE FUNCTION private.notify_task_follower_note_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  t public.tasks%ROWTYPE;
  actor UUID;
  actor_name TEXT;
  u UUID;
  note_id UUID;
BEGIN
  IF TG_OP = 'DELETE' THEN
    actor := OLD.created_by;
    note_id := OLD.id;
    SELECT * INTO t FROM public.tasks WHERE id = OLD.task_id;
  ELSE
    actor := COALESCE(auth.uid(), NEW.created_by);
    note_id := NEW.id;
    SELECT * INTO t FROM public.tasks WHERE id = NEW.task_id;
  END IF;

  IF NOT FOUND THEN IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END IF;

  SELECT COALESCE(full_name, 'User') INTO actor_name
  FROM public.profiles WHERE id = actor;
  actor_name := COALESCE(actor_name, 'User');

  FOR u IN
    SELECT DISTINCT x.user_id
    FROM (VALUES (t.created_by), (t.responsible_id), (t.follower_id)) AS x(user_id)
    WHERE x.user_id IS NOT NULL
  LOOP
    PERFORM private.insert_activity_notification(
      u, actor,
      CASE WHEN TG_OP = 'INSERT' THEN 'task_follower_note' ELSE 'task_follower_note_update' END,
      CASE WHEN TG_OP = 'INSERT' THEN 'ملاحظة متابعة جديدة' ELSE 'تحديث ملاحظة متابعة' END,
      CASE WHEN TG_OP = 'INSERT' THEN 'New Follow-up Note' ELSE 'Follow-up Note Updated' END,
      CASE WHEN TG_OP = 'INSERT'
        THEN actor_name || ' أضاف ملاحظة متابعة للمهمة: ' || t.title
        ELSE actor_name || ' حدّث ملاحظة متابعة للمهمة: ' || t.title END,
      CASE WHEN TG_OP = 'INSERT'
        THEN actor_name || ' added a follow-up note to the task: ' || t.title
        ELSE actor_name || ' updated a follow-up note on the task: ' || t.title END,
      'task', t.id,
      'task_follower_note:' || note_id::TEXT || ':' || TG_OP || ':' || COALESCE(CASE WHEN TG_OP = 'DELETE' THEN OLD.updated_at ELSE NEW.updated_at END, NOW())::TEXT || ':' || u::TEXT
    );
  END LOOP;

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;

DROP TRIGGER IF EXISTS task_follower_notes_activity_notify ON public.task_follower_notes;
CREATE TRIGGER task_follower_notes_activity_notify
AFTER INSERT OR UPDATE OR DELETE ON public.task_follower_notes
FOR EACH ROW EXECUTE FUNCTION private.notify_task_follower_note_activity();

/* ================================================================
   4) Task stages: create / edit / delete
   ================================================================ */

CREATE OR REPLACE FUNCTION private.notify_task_stage_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  task_id UUID;
  actor UUID;
  stage_id UUID;
  stage_title TEXT;
  task_title TEXT;
  actor_name TEXT;
  u UUID;
  action_ar TEXT;
  action_en TEXT;
BEGIN
  task_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.task_id ELSE NEW.task_id END;
  actor := CASE WHEN TG_OP = 'DELETE' THEN COALESCE(auth.uid(), OLD.created_by) ELSE COALESCE(auth.uid(), NEW.created_by) END;
  stage_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;
  stage_title := CASE WHEN TG_OP = 'DELETE' THEN OLD.title ELSE NEW.title END;

  SELECT title INTO task_title
  FROM public.tasks
  WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.task_id ELSE NEW.task_id END;

  IF task_title IS NULL THEN IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END IF;

  -- Re-read task participants without overloading variables.
  FOR u IN
    SELECT DISTINCT x.user_id
    FROM public.tasks t
    CROSS JOIN LATERAL (VALUES (t.created_by), (t.responsible_id), (t.follower_id)) AS x(user_id)
    WHERE t.id = CASE WHEN TG_OP = 'DELETE' THEN OLD.task_id ELSE NEW.task_id END
      AND x.user_id IS NOT NULL
  LOOP
    SELECT COALESCE(full_name, 'User') INTO actor_name
    FROM public.profiles WHERE id = actor;
    actor_name := COALESCE(actor_name, 'User');

    IF TG_OP = 'INSERT' THEN
      action_ar := 'أضاف جزءًا جديدًا للمهمة: ' || stage_title;
      action_en := 'added a new task stage: ' || stage_title;
    ELSIF TG_OP = 'UPDATE' THEN
      action_ar := 'حدّث جزء المهمة: ' || stage_title;
      action_en := 'updated the task stage: ' || stage_title;
    ELSE
      action_ar := 'حذف جزء المهمة: ' || stage_title;
      action_en := 'deleted the task stage: ' || stage_title;
    END IF;

    PERFORM private.insert_activity_notification(
      u, actor, 'task_stage',
      'تحديث أجزاء المهمة', 'Task Stage Update',
      actor_name || ' ' || action_ar || ' — ' || task_title,
      actor_name || ' ' || action_en || ' — ' || task_title,
      'task', CASE WHEN TG_OP = 'DELETE' THEN OLD.task_id ELSE NEW.task_id END,
      'task_stage:' || stage_id::TEXT || ':' || TG_OP || ':' || COALESCE(CASE WHEN TG_OP = 'DELETE' THEN OLD.updated_at ELSE NEW.updated_at END, NOW())::TEXT || ':' || u::TEXT
    );
  END LOOP;

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;

DROP TRIGGER IF EXISTS task_stages_activity_notify ON public.task_stages;
CREATE TRIGGER task_stages_activity_notify
AFTER INSERT OR UPDATE OR DELETE ON public.task_stages
FOR EACH ROW EXECUTE FUNCTION private.notify_task_stage_activity();

/* ================================================================
   5) Daily work log - every new/update/delete entry
   ================================================================ */

CREATE OR REPLACE FUNCTION private.notify_daily_task_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  t public.tasks%ROWTYPE;
  actor UUID;
  actor_name TEXT;
  u UUID;
  qty TEXT;
  stage_name TEXT;
  update_id UUID;
  task_id UUID;
BEGIN
  actor := CASE WHEN TG_OP = 'DELETE' THEN COALESCE(auth.uid(), OLD.created_by) ELSE COALESCE(auth.uid(), NEW.created_by) END;
  update_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;
  task_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.task_id ELSE NEW.task_id END;

  SELECT * INTO t FROM public.tasks WHERE id = task_id;
  IF NOT FOUND THEN IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END IF;

  SELECT COALESCE(full_name, 'User') INTO actor_name
  FROM public.profiles WHERE id = actor;
  actor_name := COALESCE(actor_name, 'User');

  IF TG_OP = 'DELETE' THEN
    qty := NULL;
  ELSE
    qty := CASE WHEN NEW.quantity_done IS NULL THEN NULL ELSE trim(to_char(NEW.quantity_done, 'FM999999990.##')) END;
  END IF;

  IF (CASE WHEN TG_OP = 'DELETE' THEN OLD.stage_id ELSE NEW.stage_id END) IS NOT NULL THEN
    SELECT title INTO stage_name
    FROM public.task_stages
    WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.stage_id ELSE NEW.stage_id END;
  END IF;

  FOR u IN
    SELECT DISTINCT x.user_id
    FROM (VALUES (t.created_by), (t.responsible_id), (t.follower_id)) AS x(user_id)
    WHERE x.user_id IS NOT NULL
  LOOP
    PERFORM private.insert_activity_notification(
      u, actor, 'task_daily_update',
      CASE WHEN TG_OP = 'INSERT' THEN 'إنجاز يومي جديد' WHEN TG_OP = 'UPDATE' THEN 'تحديث إنجاز يومي' ELSE 'حذف إنجاز يومي' END,
      CASE WHEN TG_OP = 'INSERT' THEN 'New Daily Achievement' WHEN TG_OP = 'UPDATE' THEN 'Daily Achievement Updated' ELSE 'Daily Achievement Deleted' END,
      actor_name || ' ' || CASE WHEN TG_OP = 'INSERT' THEN 'سجّل إنجازًا يوميًا في المهمة: ' WHEN TG_OP = 'UPDATE' THEN 'حدّث الإنجاز اليومي في المهمة: ' ELSE 'حذف إنجازًا يوميًا من المهمة: ' END || t.title || CASE WHEN qty IS NOT NULL THEN ' — ' || qty || ' ' || COALESCE(t.quantity_unit, 'وحدة') ELSE '' END,
      actor_name || ' ' || CASE WHEN TG_OP = 'INSERT' THEN 'recorded a daily achievement in the task: ' WHEN TG_OP = 'UPDATE' THEN 'updated a daily achievement in the task: ' ELSE 'deleted a daily achievement from the task: ' END || t.title || CASE WHEN qty IS NOT NULL THEN ' — ' || qty || ' ' || COALESCE(t.quantity_unit, 'units') ELSE '' END,
      'task', t.id,
      'task_daily_update:' || update_id::TEXT || ':' || TG_OP || ':' || COALESCE(CASE WHEN TG_OP = 'DELETE' THEN OLD.updated_at ELSE NEW.updated_at END, NOW())::TEXT || ':' || u::TEXT
    );
  END LOOP;

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;

DROP TRIGGER IF EXISTS task_daily_update_notify ON public.task_daily_updates;
DROP TRIGGER IF EXISTS task_daily_updates_notify ON public.task_daily_updates;
CREATE TRIGGER task_daily_update_notify
AFTER INSERT OR UPDATE OR DELETE ON public.task_daily_updates
FOR EACH ROW EXECUTE FUNCTION private.notify_daily_task_update();

/* ================================================================
   6) Replies to messages
   ================================================================ */

CREATE OR REPLACE FUNCTION private.notify_message_comment_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  m public.messages%ROWTYPE;
  actor_name TEXT;
  u UUID;
BEGIN
  SELECT * INTO m FROM public.messages WHERE id = NEW.message_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  SELECT COALESCE(full_name, 'User') INTO actor_name
  FROM public.profiles WHERE id = NEW.created_by;
  actor_name := COALESCE(actor_name, 'User');

  FOR u IN
    SELECT DISTINCT q.user_id
    FROM (
      SELECT mr.user_id FROM public.message_recipients mr WHERE mr.message_id = NEW.message_id
      UNION
      SELECT m.created_by
    ) q
    WHERE q.user_id IS NOT NULL
  LOOP
    PERFORM private.insert_activity_notification(
      u, NEW.created_by, 'message_reply',
      'رد جديد على الرسالة', 'New Message Reply',
      CASE WHEN NULLIF(trim(COALESCE(NEW.content, '')), '') IS NULL
        THEN actor_name || ' أرفق ملفًا في الرد على رسالة'
        ELSE actor_name || ' رد على رسالة: ' || left(NEW.content, 120) END,
      CASE WHEN NULLIF(trim(COALESCE(NEW.content, '')), '') IS NULL
        THEN actor_name || ' attached a file in a message reply'
        ELSE actor_name || ' replied to a message: ' || left(NEW.content, 120) END,
      'message', m.id,
      'message_reply:' || NEW.id::TEXT || ':' || u::TEXT
    );
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS message_comments_activity_notify ON public.message_comments;
CREATE TRIGGER message_comments_activity_notify
AFTER INSERT ON public.message_comments
FOR EACH ROW EXECUTE FUNCTION private.notify_message_comment_activity();

/* ================================================================
   7) Direct task attachments
   Comment/daily-update attachments already belong to an activity and
   should not create duplicate notifications.
   ================================================================ */

CREATE OR REPLACE FUNCTION private.notify_task_attachment_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  t public.tasks%ROWTYPE;
  actor_name TEXT;
  u UUID;
BEGIN
  IF NEW.task_id IS NULL OR NEW.task_comment_id IS NOT NULL OR NEW.daily_update_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT * INTO t FROM public.tasks WHERE id = NEW.task_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  SELECT COALESCE(full_name, 'User') INTO actor_name
  FROM public.profiles WHERE id = NEW.uploaded_by;
  actor_name := COALESCE(actor_name, 'User');

  FOR u IN
    SELECT DISTINCT x.user_id
    FROM (VALUES (t.created_by), (t.responsible_id), (t.follower_id)) AS x(user_id)
    WHERE x.user_id IS NOT NULL
  LOOP
    PERFORM private.insert_activity_notification(
      u, NEW.uploaded_by, 'task_attachment',
      'مرفق جديد في المهمة', 'New Task Attachment',
      actor_name || ' أرفق الملف: ' || NEW.file_name || ' في المهمة: ' || t.title,
      actor_name || ' attached the file: ' || NEW.file_name || ' to the task: ' || t.title,
      'task', t.id,
      'task_attachment:' || NEW.id::TEXT || ':' || u::TEXT
    );
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS attachments_task_activity_notify ON public.attachments;
CREATE TRIGGER attachments_task_activity_notify
AFTER INSERT ON public.attachments
FOR EACH ROW EXECUTE FUNCTION private.notify_task_attachment_activity();

/* ================================================================
   8) Realtime publication for activity tables
   ================================================================ */

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='task_follower_notes') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.task_follower_notes;
    END IF;
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;


NOTIFY pgrst, 'reload schema';
COMMIT;

/* Verification */
SELECT tgname, tgrelid::regclass
FROM pg_trigger
WHERE NOT tgisinternal
  AND tgname IN (
    'task_comments_activity_notify',
    'task_follower_notes_activity_notify',
    'task_stages_activity_notify',
    'task_daily_update_notify',
    'message_comments_activity_notify',
    'attachments_task_activity_notify'
  )
ORDER BY tgrelid::regclass::text, tgname;

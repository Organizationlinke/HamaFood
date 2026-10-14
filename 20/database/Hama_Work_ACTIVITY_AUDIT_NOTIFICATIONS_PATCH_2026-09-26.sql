-- Hama Work: activity/audit metadata + precise notifications
-- Run after the current core/admin patches. Safe to re-run.
BEGIN;

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS actor_id UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'notifications_actor_id_fkey'
      AND conrelid = 'public.notifications'::regclass
  ) THEN
    ALTER TABLE public.notifications
      ADD CONSTRAINT notifications_actor_id_fkey
      FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS notifications_actor_id_idx
  ON public.notifications(actor_id);

-- New/updated task notifications carry the actor and a precise action sentence.
CREATE OR REPLACE FUNCTION private.notify_task_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user UUID;
  v_actor_name TEXT;
  v_action TEXT;
BEGIN
  SELECT COALESCE(p.full_name, 'User') INTO v_actor_name
  FROM public.profiles p WHERE p.id = auth.uid();

  IF TG_OP = 'INSERT' THEN
    FOREACH v_user IN ARRAY ARRAY[NEW.responsible_id, NEW.follower_id]::UUID[] LOOP
      IF v_user IS NOT NULL AND v_user <> NEW.created_by THEN
        INSERT INTO public.notifications(user_id,type,title,body,target_type,target_id,dedupe_key,actor_id)
        VALUES(
          v_user, 'task_created', 'New Task',
          COALESCE(v_actor_name,'System') || ' created the task: ' || NEW.title,
          'task', NEW.id,
          'task_created:' || NEW.id::TEXT || ':' || v_user::TEXT,
          auth.uid()
        ) ON CONFLICT (dedupe_key) DO NOTHING;
      END IF;
    END LOOP;
  ELSIF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    v_action := CASE NEW.status::TEXT
      WHEN 'in_progress' THEN 'started the task'
      WHEN 'ready_for_completion' THEN 'requested completion for the task'
      WHEN 'completed' THEN 'completed the task'
      WHEN 'cancelled' THEN 'cancelled the task'
      WHEN 'not_started' THEN 'returned the task to Not Started'
      ELSE 'changed the task status to ' || NEW.status::TEXT
    END;

    FOREACH v_user IN ARRAY ARRAY[NEW.responsible_id, NEW.follower_id, NEW.created_by]::UUID[] LOOP
      IF v_user IS NOT NULL AND v_user <> auth.uid() THEN
        INSERT INTO public.notifications(user_id,type,title,body,target_type,target_id,dedupe_key,actor_id)
        VALUES(
          v_user, 'task_status', 'Task Update',
          COALESCE(v_actor_name,'System') || ' ' || v_action || ': ' || NEW.title,
          'task', NEW.id,
          'task_status:' || NEW.id::TEXT || ':' || NEW.status::TEXT || ':' || v_user::TEXT,
          auth.uid()
        ) ON CONFLICT (dedupe_key) DO NOTHING;
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
  v_actor_name TEXT;
  v_body TEXT;
BEGIN
  SELECT * INTO t FROM public.tasks WHERE id = NEW.task_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  SELECT COALESCE(p.full_name, 'User') INTO v_actor_name
  FROM public.profiles p WHERE p.id = NEW.created_by;

  v_body := COALESCE(v_actor_name,'User') || ' recorded ' ||
            trim(to_char(NEW.quantity_done, 'FM999999990.##')) || ' ' ||
            COALESCE(t.quantity_unit, 'units') || ' on task: ' || t.title;

  FOREACH u IN ARRAY ARRAY[t.created_by, t.responsible_id, t.follower_id]::UUID[] LOOP
    IF u IS NOT NULL AND u <> NEW.created_by THEN
      INSERT INTO public.notifications(user_id,type,title,body,target_type,target_id,dedupe_key,actor_id)
      VALUES(
        u, 'daily_progress', 'Daily Progress', v_body,
        'task', t.id,
        'daily_progress:' || NEW.id::TEXT || ':' || u::TEXT,
        NEW.created_by
      ) ON CONFLICT (dedupe_key) DO NOTHING;
    END IF;
  END LOOP;

  IF t.created_by <> NEW.created_by THEN
    INSERT INTO public.notifications(user_id,type,title,body,target_type,target_id,dedupe_key,actor_id)
    SELECT p.id, 'daily_progress', 'Daily Progress', v_body,
           'task', t.id,
           'daily_progress:' || NEW.id::TEXT || ':manager:' || p.id::TEXT,
           NEW.created_by
    FROM public.profiles p
    WHERE p.is_active = TRUE
      AND p.role IN ('gm','manager')
      AND p.id <> NEW.created_by
    ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS task_daily_updates_notify ON public.task_daily_updates;
CREATE TRIGGER task_daily_updates_notify
AFTER INSERT OR UPDATE ON public.task_daily_updates
FOR EACH ROW EXECUTE FUNCTION private.notify_daily_task_update();

NOTIFY pgrst, 'reload schema';
COMMIT;

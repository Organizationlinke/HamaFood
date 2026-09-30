-- Hama Work Core - Task Progress Tracking
-- Run AFTER the current Hama Work Core database patches.
BEGIN;

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS total_quantity NUMERIC(18,3),
  ADD COLUMN IF NOT EXISTS quantity_unit TEXT;

CREATE TABLE IF NOT EXISTS public.task_stages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  deadline TIMESTAMPTZ NOT NULL,
  target_quantity NUMERIC(18,3),
  quantity_unit TEXT,
  sort_order INTEGER NOT NULL DEFAULT 1,
  created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.task_daily_updates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  stage_id UUID REFERENCES public.task_stages(id) ON DELETE CASCADE,
  work_date DATE NOT NULL DEFAULT CURRENT_DATE,
  quantity_done NUMERIC(18,3) NOT NULL DEFAULT 0 CHECK (quantity_done >= 0),
  work_note TEXT,
  created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS task_stages_task_idx
  ON public.task_stages(task_id, sort_order, deadline);
CREATE INDEX IF NOT EXISTS task_daily_updates_task_idx
  ON public.task_daily_updates(task_id, work_date DESC);
CREATE INDEX IF NOT EXISTS task_daily_updates_stage_idx
  ON public.task_daily_updates(stage_id, work_date DESC);
CREATE INDEX IF NOT EXISTS task_daily_updates_user_idx
  ON public.task_daily_updates(created_by, work_date DESC);

-- Multiple achievement/work-log rows are intentionally allowed on the same day.
-- Do not recreate the old unique-day index.
DROP INDEX IF EXISTS public.task_daily_updates_unique_day;

CREATE OR REPLACE FUNCTION public.set_task_progress_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS task_stages_updated_at ON public.task_stages;
CREATE TRIGGER task_stages_updated_at
BEFORE UPDATE ON public.task_stages
FOR EACH ROW EXECUTE FUNCTION public.set_task_progress_updated_at();

DROP TRIGGER IF EXISTS task_daily_updates_updated_at ON public.task_daily_updates;
CREATE TRIGGER task_daily_updates_updated_at
BEFORE UPDATE ON public.task_daily_updates
FOR EACH ROW EXECUTE FUNCTION public.set_task_progress_updated_at();

ALTER TABLE public.task_stages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_daily_updates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_stages_select ON public.task_stages;
CREATE POLICY task_stages_select ON public.task_stages
FOR SELECT TO authenticated
USING (private.can_access_task(task_id));

DROP POLICY IF EXISTS task_stages_insert ON public.task_stages;
CREATE POLICY task_stages_insert ON public.task_stages
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND (
    private.is_manager()
    OR EXISTS (
      SELECT 1 FROM public.tasks t
      WHERE t.id = task_id AND t.created_by = auth.uid()
    )
  )
);

DROP POLICY IF EXISTS task_stages_update ON public.task_stages;
CREATE POLICY task_stages_update ON public.task_stages
FOR UPDATE TO authenticated
USING (private.is_manager() OR created_by = auth.uid())
WITH CHECK (private.is_manager() OR created_by = auth.uid());

DROP POLICY IF EXISTS task_stages_delete ON public.task_stages;
CREATE POLICY task_stages_delete ON public.task_stages
FOR DELETE TO authenticated
USING (private.is_manager() OR created_by = auth.uid());

DROP POLICY IF EXISTS task_daily_updates_select ON public.task_daily_updates;
CREATE POLICY task_daily_updates_select ON public.task_daily_updates
FOR SELECT TO authenticated
USING (private.can_access_task(task_id));

DROP POLICY IF EXISTS task_daily_updates_insert ON public.task_daily_updates;
CREATE POLICY task_daily_updates_insert ON public.task_daily_updates
FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND (
    private.is_manager()
    OR EXISTS (
      SELECT 1 FROM public.tasks t
      WHERE t.id = task_id
        AND (t.responsible_id = auth.uid() OR t.follower_id = auth.uid())
    )
  )
);

DROP POLICY IF EXISTS task_daily_updates_update ON public.task_daily_updates;
CREATE POLICY task_daily_updates_update ON public.task_daily_updates
FOR UPDATE TO authenticated
USING (created_by = auth.uid() OR private.is_manager())
WITH CHECK (created_by = auth.uid() OR private.is_manager());

DROP POLICY IF EXISTS task_daily_updates_delete ON public.task_daily_updates;
CREATE POLICY task_daily_updates_delete ON public.task_daily_updates
FOR DELETE TO authenticated
USING (created_by = auth.uid() OR private.is_manager());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.task_stages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.task_daily_updates TO authenticated;

-- Notify managers/GM when a daily achievement is recorded.
CREATE OR REPLACE FUNCTION private.notify_daily_task_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  t public.tasks%ROWTYPE;
  u UUID;
BEGIN
  SELECT * INTO t FROM public.tasks WHERE id = NEW.task_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  FOREACH u IN ARRAY ARRAY[t.created_by, t.responsible_id, t.follower_id]::UUID[] LOOP
    IF u IS NOT NULL AND u <> NEW.created_by THEN
      INSERT INTO public.notifications(
        user_id, type, title, body, target_type, target_id, dedupe_key
      )
      VALUES(
        u,
        'daily_progress',
        'Daily Progress Updated',
        t.title,
        'task',
        t.id,
        'daily_progress:' || NEW.id::TEXT || ':' || u::TEXT
      )
      ON CONFLICT (dedupe_key) DO NOTHING;
    END IF;
  END LOOP;

  IF t.created_by <> NEW.created_by THEN
    INSERT INTO public.notifications(
      user_id, type, title, body, target_type, target_id, dedupe_key
    )
    SELECT
      p.id,
      'daily_progress',
      'Daily Progress Updated',
      t.title,
      'task',
      t.id,
      'daily_progress:' || NEW.id::TEXT || ':manager:' || p.id::TEXT
    FROM public.profiles p
    WHERE p.is_active = TRUE
      AND p.role IN ('gm','manager')
      AND p.id <> NEW.created_by
    ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS task_daily_update_notify ON public.task_daily_updates;
CREATE TRIGGER task_daily_update_notify
AFTER INSERT OR UPDATE ON public.task_daily_updates
FOR EACH ROW EXECUTE FUNCTION private.notify_daily_task_update();

NOTIFY pgrst, 'reload schema';
COMMIT;

SELECT table_name
FROM information_schema.tables
WHERE table_schema='public'
  AND table_name IN ('task_stages','task_daily_updates')
ORDER BY table_name;

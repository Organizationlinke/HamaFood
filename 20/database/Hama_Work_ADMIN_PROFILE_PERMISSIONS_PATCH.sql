-- Hama Work: Admin controls + profile + permissions
-- Run AFTER the current core/progress patches.
BEGIN;

-- 1) Profile avatar URL.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS avatar_url TEXT;


-- 1b) Soft-delete / Trash support. Deleted tasks are hidden from normal task lists.
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS deleted_from_status public.task_status;

-- 2) Per-user permissions.
CREATE TABLE IF NOT EXISTS public.user_permissions (
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  permission_key TEXT NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, permission_key)
);

ALTER TABLE public.user_permissions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_permissions_select ON public.user_permissions;
DROP POLICY IF EXISTS user_permissions_insert ON public.user_permissions;
DROP POLICY IF EXISTS user_permissions_update ON public.user_permissions;
DROP POLICY IF EXISTS user_permissions_delete ON public.user_permissions;

CREATE POLICY user_permissions_select ON public.user_permissions
FOR SELECT TO authenticated
USING (private.is_gm() OR user_id = auth.uid());

CREATE POLICY user_permissions_insert ON public.user_permissions
FOR INSERT TO authenticated
WITH CHECK (private.is_gm());

CREATE POLICY user_permissions_update ON public.user_permissions
FOR UPDATE TO authenticated
USING (private.is_gm())
WITH CHECK (private.is_gm());

CREATE POLICY user_permissions_delete ON public.user_permissions
FOR DELETE TO authenticated
USING (private.is_gm());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_permissions TO authenticated;

-- 3) GM-only task edit/delete RPCs. These avoid depending on whatever task RLS
-- policies are currently installed while still enforcing the permission server-side.
CREATE OR REPLACE FUNCTION public.admin_update_task(
  p_task_id UUID,
  p_title TEXT,
  p_description TEXT,
  p_priority TEXT,
  p_deadline TIMESTAMPTZ,
  p_responsible_id UUID,
  p_follower_id UUID DEFAULT NULL,
  p_evidence_required BOOLEAN DEFAULT NULL,
  p_manager_confirmation_required BOOLEAN DEFAULT NULL,
  p_total_quantity NUMERIC DEFAULT NULL,
  p_quantity_unit TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.is_gm() THEN
    RAISE EXCEPTION 'Only the General Manager can edit tasks';
  END IF;
  UPDATE public.tasks
  SET title = p_title,
      description = NULLIF(BTRIM(p_description), ''),
      priority = p_priority::public.priority_level,
      deadline = p_deadline,
      responsible_id = p_responsible_id,
      follower_id = p_follower_id,
      evidence_required = COALESCE(p_evidence_required, evidence_required),
      manager_confirmation_required = COALESCE(p_manager_confirmation_required, manager_confirmation_required),
      total_quantity = p_total_quantity,
      quantity_unit = NULLIF(BTRIM(p_quantity_unit), ''),
      updated_at = NOW()
  WHERE id = p_task_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_task(p_task_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.is_gm() THEN
    RAISE EXCEPTION 'Only the General Manager can delete tasks';
  END IF;
  UPDATE public.tasks
  SET deleted_from_status = status,
      deleted_at = NOW(),
      deleted_by = auth.uid(),
      updated_at = NOW()
  WHERE id = p_task_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found or already deleted'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_restore_task(p_task_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.is_gm() THEN RAISE EXCEPTION 'Only the General Manager can restore tasks'; END IF;
  UPDATE public.tasks
  SET status = COALESCE(deleted_from_status, 'not_started'::public.task_status),
      deleted_from_status = NULL, deleted_at = NULL, deleted_by = NULL, updated_at = NOW()
  WHERE id = p_task_id AND deleted_at IS NOT NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Deleted task not found'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_permanently_delete_task(p_task_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.is_gm() THEN RAISE EXCEPTION 'Only the General Manager can permanently delete tasks'; END IF;
  DELETE FROM public.tasks WHERE id = p_task_id AND deleted_at IS NOT NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Deleted task not found'; END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_task(UUID,TEXT,TEXT,TEXT,TIMESTAMPTZ,UUID,UUID,BOOLEAN,BOOLEAN,NUMERIC,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_task(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_restore_task(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_permanently_delete_task(UUID) TO authenticated;

-- 4) Safe own-profile avatar update.
CREATE OR REPLACE FUNCTION public.set_my_avatar_url(p_url TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.profiles
  SET avatar_url = NULLIF(BTRIM(p_url), '')
  WHERE id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION public.set_my_avatar_url(TEXT) TO authenticated;

-- 5) Avatar storage bucket.
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', TRUE)
ON CONFLICT (id) DO UPDATE SET public = TRUE;

DROP POLICY IF EXISTS avatars_public_read ON storage.objects;
DROP POLICY IF EXISTS avatars_own_insert ON storage.objects;
DROP POLICY IF EXISTS avatars_own_update ON storage.objects;
DROP POLICY IF EXISTS avatars_own_delete ON storage.objects;

CREATE POLICY avatars_public_read ON storage.objects
FOR SELECT USING (bucket_id = 'avatars');

CREATE POLICY avatars_own_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY avatars_own_update ON storage.objects
FOR UPDATE TO authenticated
USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY avatars_own_delete ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

-- 6) Default permission rows for every active user.
INSERT INTO public.user_permissions(user_id, permission_key, enabled)
SELECT p.id, x.permission_key,
       CASE
         WHEN p.role = 'gm' THEN TRUE
         WHEN x.permission_key IN ('tasks.view','messages.view','notifications.view','profile.edit') THEN TRUE
         ELSE FALSE
       END
FROM public.profiles p
CROSS JOIN (VALUES
  ('tasks.view'),('tasks.create'),('tasks.edit'),('tasks.delete'),('tasks.cancel'),('tasks.manage_status'),('tasks.evaluate'),
  ('messages.view'),('messages.create'),('messages.manage'),('notifications.view'),
  ('users.view'),('users.create'),('users.edit'),('users.reset_password'),
  ('permissions.manage'),('profile.edit')
) x(permission_key)
ON CONFLICT (user_id, permission_key) DO NOTHING;

NOTIFY pgrst, 'reload schema';
COMMIT;


-- 7) Cancel-task permission. Only GM or users explicitly granted tasks.cancel may cancel.
CREATE OR REPLACE FUNCTION public.cancel_task(p_task_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_allowed BOOLEAN;
BEGIN
  SELECT private.is_gm() OR COALESCE((SELECT enabled FROM public.user_permissions WHERE user_id=auth.uid() AND permission_key='tasks.cancel'), FALSE) INTO v_allowed;
  IF NOT v_allowed THEN RAISE EXCEPTION 'Cancel task permission required'; END IF;
  UPDATE public.tasks SET status='cancelled'::public.task_status, updated_at=NOW()
  WHERE id=p_task_id AND deleted_at IS NULL AND status NOT IN ('completed'::public.task_status,'cancelled'::public.task_status);
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found or cannot be cancelled'; END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cancel_task(UUID) TO authenticated;

-- 8) Add avatar URLs to visible-message/recipient RPCs where supported.
DROP FUNCTION IF EXISTS public.get_message_recipients(UUID);
CREATE OR REPLACE FUNCTION public.get_message_recipients(p_message_id UUID)
RETURNS TABLE (user_id UUID, full_name TEXT, username TEXT, avatar_url TEXT, seen_at TIMESTAMPTZ)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT r.user_id,p.full_name,p.username,p.avatar_url,r.seen_at FROM public.message_recipients r
  JOIN public.profiles p ON p.id=r.user_id
  WHERE r.message_id=p_message_id
    AND (private.is_gm() OR EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.id=p_message_id
        AND (m.created_by=auth.uid() OR EXISTS (SELECT 1 FROM public.message_recipients rx WHERE rx.message_id=m.id AND rx.user_id=auth.uid()))
    ))
  ORDER BY p.full_name;
$$;
GRANT EXECUTE ON FUNCTION public.get_message_recipients(UUID) TO authenticated;

NOTIFY pgrst,'reload schema';


-- 9) Visible messages include sender avatar URL for consistent user identity UI.
DROP FUNCTION IF EXISTS public.get_visible_messages();
CREATE OR REPLACE FUNCTION public.get_visible_messages()
RETURNS TABLE (
  id UUID, code TEXT, content TEXT, message_type TEXT, audience_type TEXT, created_by UUID,
  sender_name TEXT, sender_avatar_url TEXT, task_id UUID, created_at TIMESTAMPTZ,
  recipient_count INTEGER, seen_count INTEGER, seen_by_me BOOLEAN
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT m.id,m.code,m.content,m.message_type::TEXT,m.audience_type::TEXT,m.created_by,
    COALESCE(p.full_name,'User'), p.avatar_url, m.task_id,m.created_at,
    COUNT(r.message_id)::INTEGER,
    COUNT(r.message_id) FILTER (WHERE r.seen_at IS NOT NULL)::INTEGER,
    COALESCE(BOOL_OR(r.user_id=auth.uid() AND r.seen_at IS NOT NULL),FALSE)
  FROM public.messages m
  LEFT JOIN public.profiles p ON p.id=m.created_by
  LEFT JOIN public.message_recipients r ON r.message_id=m.id
  WHERE private.is_gm() OR m.created_by=auth.uid() OR EXISTS (SELECT 1 FROM public.message_recipients rx WHERE rx.message_id=m.id AND rx.user_id=auth.uid())
  GROUP BY m.id,p.full_name,p.avatar_url
  ORDER BY m.created_at DESC LIMIT 200;
$$;
GRANT EXECUTE ON FUNCTION public.get_visible_messages() TO authenticated;

NOTIFY pgrst,'reload schema';

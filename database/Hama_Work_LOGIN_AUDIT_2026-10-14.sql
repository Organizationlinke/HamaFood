-- Hama Work: Login audit / last login timestamp
-- Purpose:
--   1) Record the successful login time for each user using Supabase server time.
--   2) Expose last_login_at only through a GM-only RPC used by the Users screen.
-- Run once in Supabase SQL Editor.

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;

-- Record a successful login for the currently authenticated user.
-- SECURITY DEFINER avoids depending on the profile UPDATE RLS policy.
CREATE OR REPLACE FUNCTION public.record_my_login()
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.profiles
  SET last_login_at = NOW()
  WHERE id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.record_my_login() TO authenticated;

-- GM-only user list. last_login_at is deliberately not exposed by the
-- normal profiles SELECT query used by other users.
CREATE OR REPLACE FUNCTION public.get_users_for_admin()
RETURNS TABLE (
  id UUID,
  username TEXT,
  full_name TEXT,
  user_code TEXT,
  role TEXT,
  department TEXT,
  preferred_language TEXT,
  is_active BOOLEAN,
  avatar_url TEXT,
  last_login_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.is_gm() THEN
    RAISE EXCEPTION 'Only the General Manager can view login audit data';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.username,
    p.full_name,
    p.user_code,
    p.role::TEXT,
    p.department,
    p.preferred_language,
    p.is_active,
    p.avatar_url,
    p.last_login_at
  FROM public.profiles p
  WHERE p.is_active = TRUE
  ORDER BY p.full_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_users_for_admin() TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Verification:
-- SELECT id, username, last_login_at FROM public.profiles ORDER BY full_name;

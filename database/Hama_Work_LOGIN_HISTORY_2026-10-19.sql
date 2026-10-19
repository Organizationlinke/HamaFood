-- HF Team: Login/session activity history
-- 2026-10-19
-- Run after Hama_Work_LOGIN_AUDIT_2026-10-14.sql

BEGIN;

CREATE TABLE IF NOT EXISTS public.login_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  login_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  source TEXT NOT NULL DEFAULT 'app_activity'
    CHECK (source IN ('app_activity', 'password_login'))
);

CREATE INDEX IF NOT EXISTS idx_login_history_user_time
  ON public.login_history(user_id, login_at DESC);

ALTER TABLE public.login_history ENABLE ROW LEVEL SECURITY;

-- History is exposed through SECURITY DEFINER RPCs so normal users only
-- receive their own records and the GM can read another user's records.
REVOKE ALL ON public.login_history FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.record_my_login()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.profiles
  SET last_login_at = NOW()
  WHERE id = auth.uid();

  INSERT INTO public.login_history(user_id, login_at, source)
  VALUES (auth.uid(), NOW(), 'app_activity');
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_my_login() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_login_history(p_limit INTEGER DEFAULT 30)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  login_at TIMESTAMPTZ,
  source TEXT
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
  SELECT h.id, h.user_id, h.login_at, h.source
  FROM public.login_history h
  WHERE h.user_id = auth.uid()
  ORDER BY h.login_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
$$;

GRANT EXECUTE ON FUNCTION public.get_my_login_history(INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_user_login_history_admin(
  p_user_id UUID,
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  login_at TIMESTAMPTZ,
  source TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
BEGIN
  IF NOT private.is_gm() THEN
    RAISE EXCEPTION 'Only the General Manager can view login history';
  END IF;

  RETURN QUERY
  SELECT h.id, h.user_id, h.login_at, h.source
  FROM public.login_history h
  WHERE h.user_id = p_user_id
  ORDER BY h.login_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_login_history_admin(UUID, INTEGER) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Optional verification:
-- SELECT * FROM public.login_history ORDER BY login_at DESC LIMIT 50;

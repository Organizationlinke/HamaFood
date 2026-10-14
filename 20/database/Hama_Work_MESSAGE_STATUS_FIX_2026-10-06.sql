-- Hama Work - Fix message status rows for legacy/sender/GM messages
-- 2026-10-06
-- Run after Hama_Work_MESSAGE_STATUS_AND_OVERDUE_INDEPENDENT_2026-10-06.sql

BEGIN;

CREATE OR REPLACE FUNCTION public.set_message_recipient_status(
  p_message_id UUID,
  p_status TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_status NOT IN ('not_started','in_progress','completed') THEN
    RAISE EXCEPTION 'Invalid message status';
  END IF;

  IF NOT (
    private.is_gm()
    OR EXISTS (
      SELECT 1
      FROM public.messages m
      WHERE m.id = p_message_id
        AND (
          m.created_by = auth.uid()
          OR EXISTS (
            SELECT 1
            FROM public.message_recipients rx
            WHERE rx.message_id = m.id
              AND rx.user_id = auth.uid()
          )
        )
    )
  ) THEN
    RAISE EXCEPTION 'Message recipient not found';
  END IF;

  INSERT INTO public.message_recipients (message_id, user_id, status, status_updated_at)
  VALUES (p_message_id, auth.uid(), p_status, NOW())
  ON CONFLICT (message_id, user_id)
  DO UPDATE SET
    status = EXCLUDED.status,
    status_updated_at = EXCLUDED.status_updated_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_message_recipient_status(UUID, TEXT) TO authenticated;

DROP FUNCTION IF EXISTS public.get_visible_messages();
CREATE OR REPLACE FUNCTION public.get_visible_messages()
RETURNS TABLE (
  id UUID, code TEXT, content TEXT, message_type TEXT, audience_type TEXT,
  created_by UUID, sender_name TEXT, sender_avatar_url TEXT, task_id UUID,
  created_at TIMESTAMPTZ, recipient_count INTEGER, seen_count INTEGER,
  seen_by_me BOOLEAN, my_status TEXT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT
    m.id, m.code, m.content, m.message_type::TEXT, m.audience_type::TEXT,
    m.created_by, COALESCE(p.full_name, 'User'), p.avatar_url, m.task_id, m.created_at,
    COUNT(r.message_id)::INTEGER,
    COUNT(r.message_id) FILTER (WHERE r.seen_at IS NOT NULL)::INTEGER,
    COALESCE(BOOL_OR(r.user_id = auth.uid() AND r.seen_at IS NOT NULL), FALSE),
    COALESCE(MAX(rme.status) FILTER (WHERE rme.user_id = auth.uid()), 'not_started')
  FROM public.messages m
  LEFT JOIN public.profiles p ON p.id = m.created_by
  LEFT JOIN public.message_recipients r ON r.message_id = m.id
  LEFT JOIN public.message_recipients rme
    ON rme.message_id = m.id AND rme.user_id = auth.uid()
  WHERE private.is_gm()
     OR m.created_by = auth.uid()
     OR EXISTS (SELECT 1 FROM public.message_recipients rx
               WHERE rx.message_id = m.id AND rx.user_id = auth.uid())
  GROUP BY m.id, p.full_name, p.avatar_url
  ORDER BY m.created_at DESC
  LIMIT 200;
$$;

GRANT EXECUTE ON FUNCTION public.get_visible_messages() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_message_status_counts()
RETURNS TABLE (not_started BIGINT, in_progress BIGINT, completed BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT
    COUNT(*) FILTER (WHERE COALESCE(r.status, 'not_started') = 'not_started'),
    COUNT(*) FILTER (WHERE COALESCE(r.status, 'not_started') = 'in_progress'),
    COUNT(*) FILTER (WHERE COALESCE(r.status, 'not_started') = 'completed')
  FROM public.messages m
  LEFT JOIN public.message_recipients r
    ON r.message_id = m.id AND r.user_id = auth.uid()
  WHERE private.is_gm()
     OR m.created_by = auth.uid()
     OR r.user_id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.get_my_message_status_counts() TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

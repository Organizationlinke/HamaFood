-- Hama Work: real-time in-app notifications.
-- Run once in Supabase SQL Editor.
-- Safe to run more than once.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
END $$;

-- Verification:
-- SELECT schemaname, tablename
-- FROM pg_publication_tables
-- WHERE pubname = 'supabase_realtime'
--   AND schemaname = 'public'
--   AND tablename = 'notifications';

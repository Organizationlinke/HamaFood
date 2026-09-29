-- Hama Work: enable Supabase Realtime for live communication.
-- Run once in Supabase SQL Editor.
-- The DO blocks make this safe to re-run.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_recipients'
  ) then
    alter publication supabase_realtime add table public.message_recipients;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_comments'
  ) then
    alter publication supabase_realtime add table public.message_comments;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'task_comments'
  ) then
    alter publication supabase_realtime add table public.task_comments;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;

-- Optional verification:
-- select schemaname, tablename
-- from pg_publication_tables
-- where pubname = 'supabase_realtime'
--   and schemaname = 'public'
-- order by tablename;

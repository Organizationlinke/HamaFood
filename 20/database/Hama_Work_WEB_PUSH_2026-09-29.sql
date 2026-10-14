-- Hama Work Web Push
-- Run once in Supabase SQL Editor.

create table if not exists public.user_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  expiration_time bigint,
  platform text not null default 'web',
  user_agent text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index if not exists user_push_subscriptions_user_id_idx
  on public.user_push_subscriptions(user_id);

create index if not exists user_push_subscriptions_active_idx
  on public.user_push_subscriptions(user_id, active);

alter table public.user_push_subscriptions enable row level security;

drop policy if exists "push subscriptions select own" on public.user_push_subscriptions;
create policy "push subscriptions select own"
on public.user_push_subscriptions
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "push subscriptions insert own" on public.user_push_subscriptions;
create policy "push subscriptions insert own"
on public.user_push_subscriptions
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "push subscriptions update own" on public.user_push_subscriptions;
create policy "push subscriptions update own"
on public.user_push_subscriptions
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "push subscriptions delete own" on public.user_push_subscriptions;
create policy "push subscriptions delete own"
on public.user_push_subscriptions
for delete
to authenticated
using (user_id = auth.uid());

-- The Edge Function uses the service role and therefore bypasses RLS.

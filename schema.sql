-- Run this once in Supabase: SQL Editor > New query > paste > Run.

-- 1) One planner per user, protected by row-level security.
create table if not exists public.planners (
                                               user_id uuid primary key references auth.users(id) on delete cascade,
    data jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now(),
    constraint planner_size check (pg_column_size(data) < 500000)
    );

alter table public.planners enable row level security;

create policy "own planner: read"   on public.planners for select using ((select auth.uid()) = user_id);
create policy "own planner: insert" on public.planners for insert with check ((select auth.uid()) = user_id);
create policy "own planner: update" on public.planners for update using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "own planner: delete" on public.planners for delete using ((select auth.uid()) = user_id);

-- Live updates between devices
alter publication supabase_realtime add table public.planners;

-- 2) Daily usage counter for the screenshot reader (protects your Anthropic bill).
create table if not exists public.scan_usage (
                                                 user_id uuid references auth.users(id) on delete cascade,
    day date not null,
    count int not null default 0,
    primary key (user_id, day)
    );
alter table public.scan_usage enable row level security;   -- no policies: browsers cannot touch it

create or replace function public.bump_scan_usage(p_user uuid, p_day date)
returns int language sql security definer set search_path = public as $$
  insert into public.scan_usage (user_id, day, count) values (p_user, p_day, 1)
  on conflict (user_id, day) do update set count = public.scan_usage.count + 1
                                           returning count;
$$;
revoke execute on function public.bump_scan_usage(uuid, date) from public, anon, authenticated;
grant  execute on function public.bump_scan_usage(uuid, date) to service_role;

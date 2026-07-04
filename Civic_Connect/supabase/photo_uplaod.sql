
-- CivicConnect — Supabase schema


create extension if not exists pgcrypto;

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role text not null default 'citizen' check (role in ('citizen','official','moderator','admin')),
  created_at timestamptz not null default now()
);

alter table profiles enable row level security;

drop policy if exists "profiles_public_read" on profiles;
create policy "profiles_public_read" on profiles
  for select using (true);

drop policy if exists "profiles_update_own" on profiles;
create policy "profiles_update_own" on profiles
  for update using (auth.uid() = id);

-- Auto-create a profile row whenever someone signs up
create or replace function handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)));
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();


-- ISSUES

create table if not exists issues (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  title text not null,
  description text not null,
  category text not null check (category in ('roads','water','electric','sanitation','drainage','other')),
  severity text not null check (severity in ('Low','Medium','High','Critical')),
  status text not null default 'Reported' check (status in ('Reported','Under Review','Assigned','In Progress','Resolved')),
  locality text,
  lat double precision not null,
  lng double precision not null,
  image_url text,
  anonymous boolean not null default false,
  support_count integer not null default 0,
  created_at timestamptz not null default now()
);

alter table issues enable row level security;

-- Anyone (including logged-out visitors) can read issues
drop policy if exists "issues_public_read" on issues;
create policy "issues_public_read" on issues
  for select using (true);

-- Only logged-in users can create a report, and only as themselves
drop policy if exists "issues_insert_own" on issues;
create policy "issues_insert_own" on issues
  for insert with check (auth.uid() = user_id);

-- Citizens can edit their own reports; officials (see profiles above) can update any
drop policy if exists "issues_update_own_or_official" on issues;
create policy "issues_update_own_or_official" on issues
  for update using (
    auth.uid() = user_id
    or exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'official')
  );

-- ISSUE SUPPORTS  (one upvote per user per issue)

create table if not exists issue_supports (
  id uuid primary key default gen_random_uuid(),
  issue_id uuid not null references issues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (issue_id, user_id)
);

alter table issue_supports enable row level security;

drop policy if exists "supports_public_read" on issue_supports;
create policy "supports_public_read" on issue_supports
  for select using (true);

drop policy if exists "supports_insert_own" on issue_supports;
create policy "supports_insert_own" on issue_supports
  for insert with check (auth.uid() = user_id);


-- COMMUNITY DISCUSSION THREADS

create table if not exists threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  display_name text not null,
  text text not null,
  created_at timestamptz not null default now()
);

alter table threads enable row level security;

drop policy if exists "threads_public_read" on threads;
create policy "threads_public_read" on threads
  for select using (true);

drop policy if exists "threads_insert_own" on threads;
create policy "threads_insert_own" on threads
  for insert with check (auth.uid() = user_id);


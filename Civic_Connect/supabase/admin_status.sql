update profiles set role = 'official' where id = '55183c2c-4c04-4ba8-8f85-2f2eb2f94f5d';

create table if not exists events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  event_date date not null,
  location_time text,      -- free text, e.g. "Ward 2 · 8:00 AM"
  volunteers integer default 0,
  created_at timestamptz not null default now()
);

alter table events enable row level security;

drop policy if exists "events_public_read" on events;
create policy "events_public_read" on events
  for select using (true);

drop policy if exists "events_official_insert" on events;
create policy "events_official_insert" on events
  for insert with check (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'official')
  );

drop policy if exists "events_official_update" on events;
create policy "events_official_update" on events
  for update using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'official')
  );

drop policy if exists "events_official_delete" on events;
create policy "events_official_delete" on events
  for delete using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'official')
  );

drop policy if exists "threads_delete_own_or_official" on threads;
create policy "threads_delete_own_or_official" on threads
  for delete using (
    auth.uid() = user_id
    or exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'official')
  );



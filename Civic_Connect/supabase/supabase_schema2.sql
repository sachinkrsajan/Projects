-- =====================================================================
-- CivicConnect — Resolution Proof / Verification / Timeline / Notifications
-- Run this in the Supabase SQL editor. Assumes the existing "issues" and
-- "profiles" tables already exist from the original project.
-- =====================================================================

-- ---------------------------------------------------------------------
-- FEATURE 5: resolution_proofs
-- ---------------------------------------------------------------------
create table if not exists public.resolution_proofs (
  id uuid primary key default gen_random_uuid(),
  issue_id uuid not null references public.issues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  image_url text not null,
  comment text,
  status text not null default 'Pending' check (status in ('Pending','Approved','Rejected')),
  uploaded_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id),
  admin_comment text
);

create index if not exists resolution_proofs_issue_id_idx on public.resolution_proofs(issue_id);
create index if not exists resolution_proofs_user_id_idx on public.resolution_proofs(user_id);
create index if not exists resolution_proofs_status_idx on public.resolution_proofs(status);

alter table public.resolution_proofs enable row level security;

-- Citizens: insert only their own proof
create policy "citizens can insert own proof"
  on public.resolution_proofs for insert
  to authenticated
  with check (user_id = auth.uid());

-- Citizens: read only their own proof
create policy "citizens can read own proof"
  on public.resolution_proofs for select
  to authenticated
  using (user_id = auth.uid());

-- Admins: read everything
create policy "admins can read all proofs"
  on public.resolution_proofs for select
  to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

-- Admins: update everything (approve/reject)
create policy "admins can update all proofs"
  on public.resolution_proofs for update
  to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

-- Admins: delete everything
create policy "admins can delete all proofs"
  on public.resolution_proofs for delete
  to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

-- ---------------------------------------------------------------------
-- FEATURE 3 support: issue_timeline (date/time/user/comment per step)
-- ---------------------------------------------------------------------
create table if not exists public.issue_timeline (
  id uuid primary key default gen_random_uuid(),
  issue_id uuid not null references public.issues(id) on delete cascade,
  status text not null,
  event_type text not null default 'status_change'
    check (event_type in ('reported','status_change','proof_uploaded','approved','rejected')),
  comment text,
  user_id uuid references auth.users(id),
  actor_name text,
  created_at timestamptz not null default now()
);

create index if not exists issue_timeline_issue_id_idx on public.issue_timeline(issue_id);

alter table public.issue_timeline enable row level security;

-- Anyone signed in can read timeline entries (issues are public data on this platform)
create policy "authenticated can read timeline"
  on public.issue_timeline for select
  to authenticated
  using (true);

-- Any authenticated user can log an event for their own action (citizen report/proof upload)
-- or if they are official/admin (status changes, approvals, rejections)
create policy "authenticated can insert timeline events"
  on public.issue_timeline for insert
  to authenticated
  with check (
    user_id = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('official','admin'))
  );

-- ---------------------------------------------------------------------
-- FEATURE 4: notifications
-- ---------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  issue_id uuid references public.issues(id) on delete cascade,
  message text not null,
  type text not null default 'info' check (type in ('info','success','warning')),
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_id_idx on public.notifications(user_id);

alter table public.notifications enable row level security;

-- Users read only their own notifications
create policy "users read own notifications"
  on public.notifications for select
  to authenticated
  using (user_id = auth.uid());

-- Users can mark their own notifications as read
create policy "users update own notifications"
  on public.notifications for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Admins can insert notifications for any citizen (approve/reject flow)
create policy "admins insert notifications for anyone"
  on public.notifications for insert
  to authenticated
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

-- Users can also insert their own notifications if ever needed client-side
create policy "users insert own notifications"
  on public.notifications for insert
  to authenticated
  with check (user_id = auth.uid());

-- Enable Realtime for the notifications bell
alter publication supabase_realtime add table public.notifications;

-- ---------------------------------------------------------------------
-- Role update: profiles.role now supports 'citizen' | 'official' | 'admin'
-- (No schema change needed if role is already a free-text/enum column —
-- just make sure the check constraint, if any, allows 'admin'.)
-- Example, only run if you already have a check constraint to replace:
-- alter table public.profiles drop constraint if exists profiles_role_check;
-- alter table public.profiles add constraint profiles_role_check
--   check (role in ('citizen','official','admin'));

-- To make a user an Admin, run (after they sign up once):
-- update public.profiles set role = 'admin' where id = '<their-auth-user-uuid>';


-- =====================================================================
-- FEATURE 6: Storage — "resolution-proofs" bucket + policies
-- =====================================================================

-- Create the bucket (id and name both "resolution-proofs"), public read so
-- citizens/admins can preview images directly via public URL.
insert into storage.buckets (id, name, public)
values ('resolution-proofs', 'resolution-proofs', true)
on conflict (id) do nothing;

-- Public can view resolution proof images (needed for <img> preview URLs)
create policy "public can view resolution proofs"
  on storage.objects for select
  to public
  using (bucket_id = 'resolution-proofs');

-- Citizens can upload only into their own folder: resolution-proofs/{auth.uid()}/...
create policy "citizens can upload own resolution proofs"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'resolution-proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Citizens can update/replace only their own files
create policy "citizens can update own resolution proofs"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'resolution-proofs' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'resolution-proofs' and (storage.foldername(name))[1] = auth.uid()::text);

-- Citizens can delete only their own files; admins can delete anything in the bucket
create policy "citizens delete own resolution proofs"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'resolution-proofs'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
    )
  );
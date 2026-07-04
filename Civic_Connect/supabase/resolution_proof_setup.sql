
-- CivicConnect — Resolution Proof feature
-- TABLE

create table if not exists resolution_proofs (
  id uuid primary key default gen_random_uuid(),
  issue_id uuid not null references issues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  image_url text not null,
  comment text default '',
  status text not null default 'Pending' check (status in ('Pending','Approved','Rejected')),
  uploaded_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id),
  admin_comment text
);

create index if not exists resolution_proofs_issue_idx on resolution_proofs(issue_id);
create index if not exists resolution_proofs_user_idx on resolution_proofs(user_id);
create index if not exists resolution_proofs_status_idx on resolution_proofs(status);

alter table resolution_proofs enable row level security;

-- Public read: anyone can see proof status/photos for any issue (matches how
-- issues themselves are public in this app)
drop policy if exists "resolution_proofs_select" on resolution_proofs;
create policy "resolution_proofs_select" on resolution_proofs
  for select using (true);

-- Any signed-in user can submit a proof for any issue (not just the original reporter)
drop policy if exists "resolution_proofs_insert" on resolution_proofs;
create policy "resolution_proofs_insert" on resolution_proofs
  for insert with check (
    auth.uid() = user_id
    and auth.uid() is not null
  );

-- Officials (or admins, if you still use that role) can update a proof's review status
drop policy if exists "resolution_proofs_admin_update" on resolution_proofs;
create policy "resolution_proofs_admin_update" on resolution_proofs
  for update using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('official','admin'))
  );

-- STORAGE — "resolution-proofs" bucket

insert into storage.buckets (id, name, public)
values ('resolution-proofs', 'resolution-proofs', true)
on conflict (id) do nothing;

drop policy if exists "resolution_proofs_public_read" on storage.objects;
create policy "resolution_proofs_public_read" on storage.objects
  for select using (bucket_id = 'resolution-proofs');

drop policy if exists "resolution_proofs_owner_upload" on storage.objects;
create policy "resolution_proofs_owner_upload" on storage.objects
  for insert with check (
    bucket_id = 'resolution-proofs'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "resolution_proofs_admin_update" on resolution_proofs;
create policy "resolution_proofs_admin_update" on resolution_proofs
  for update using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('official','admin'))
  );
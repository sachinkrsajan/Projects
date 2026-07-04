-- Allow anyone to view/read photos in the bucket (since it's public)
create policy "issue_photos_public_read"
on storage.objects for select
using ( bucket_id = 'issue-photos' );

-- Allow any logged-in user to upload photos to the bucket
create policy "issue_photos_authenticated_upload"
on storage.objects for insert
with check ( bucket_id = 'issue-photos' and auth.role() = 'authenticated' );


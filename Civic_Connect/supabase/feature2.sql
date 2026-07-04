
-- CivicConnect — Feature 2 migration

alter table issues add column if not exists resolution_image_url text;
-- ============================================================
-- CivicConnect — Feature 2 migration
-- Run this once in Supabase SQL Editor before testing the dashboard.
-- Safe to re-run (idempotent).
-- ============================================================
 
-- Stores the "proof of completion" photo an official uploads,
-- kept separate from the citizen's original report photo (image_url).
alter table issues add column if not exists resolution_image_url text;
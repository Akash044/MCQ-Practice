-- Adds a free-text lecture-notes field to folders (used for subfolders only
-- at the app layer, but kept on the shared folders table rather than a new
-- one since it's a single optional field per row).
-- Run this once against your existing Supabase project (SQL editor or
-- `supabase db execute`) — schema.sql alone only affects fresh databases.

alter table folders add column if not exists notes text;

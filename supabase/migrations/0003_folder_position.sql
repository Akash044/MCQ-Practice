-- Adds manual drag-reorder support for folders and subfolders, mirroring
-- 0001_question_set_position.sql for question_sets. Siblings are folders
-- sharing the same parent_id (null counts as a shared "root" group).
-- Run this once against your existing Supabase project (SQL editor or
-- `supabase db execute`) — schema.sql alone only affects fresh databases.

alter table folders add column if not exists position int not null default 0;

-- Backfill existing rows so they keep roughly their current (alphabetical)
-- order instead of all collapsing to position 0.
with ranked as (
  select id, row_number() over (partition by parent_id order by name) - 1 as rn
  from folders
)
update folders f
set position = ranked.rn
from ranked
where f.id = ranked.id;

-- Adds manual drag-reorder support for exams (question_sets) within a folder.
-- Run this once against your existing Supabase project (SQL editor or
-- `supabase db execute`) — schema.sql alone only affects fresh databases.

alter table question_sets add column if not exists position int not null default 0;

-- Backfill existing rows so they keep their current (newest-first) order
-- instead of all collapsing to position 0.
with ranked as (
  select id, row_number() over (partition by folder_id order by created_at desc) - 1 as rn
  from question_sets
)
update question_sets qs
set position = ranked.rn
from ranked
where qs.id = ranked.id;

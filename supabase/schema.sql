-- MCQ Exam & Progress Tracker — Supabase schema
-- See docs/PRD.md section 6 for design rationale.

create extension if not exists pgcrypto;

-- Organizing structure: "BCS Model Test", "Bangladesh Affairs", etc.
-- parent_id is self-referencing so folders can nest if desired.
create table folders (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  parent_id uuid references folders(id) on delete cascade,
  created_at timestamptz default now()
);

-- One row per imported JSON file, belongs to a folder.
create table question_sets (
  id uuid primary key default gen_random_uuid(),
  folder_id uuid references folders(id) on delete cascade,
  title text not null,              -- from "exam_title" in the JSON
  subject text,                     -- from "subject" in the JSON
  default_marks_per_correct numeric default 1,
  default_negative_marks_per_wrong numeric default 0,
  position int not null default 0,  -- manual drag-order within the folder
  created_at timestamptz default now()
);

-- One row per question.
create table questions (
  id uuid primary key default gen_random_uuid(),
  question_set_id uuid references question_sets(id) on delete cascade,
  source_id text,                -- the "id" from the JSON, for traceability
  question_text text not null,
  options jsonb not null,        -- array of option strings
  correct_answer int not null,   -- index into options
  explanation text,
  topic text,
  difficulty text,
  created_at timestamptz default now()
);

-- One row per exam session taken (a set can be attempted any number of times).
create table attempts (
  id uuid primary key default gen_random_uuid(),
  question_set_id uuid references question_sets(id),
  source_type text check (source_type in ('full_set','wrong_answers_retry','skipped_retry','custom')) default 'full_set',
  mode text check (mode in ('practice','test')),
  marks_per_correct numeric not null default 1,
  negative_marks_per_wrong numeric not null default 0,
  exam_timer_minutes int,             -- null = untimed overall
  per_question_timer_seconds int,     -- null = untimed per question
  total_questions int not null,
  correct_count int not null default 0,
  wrong_count int not null default 0,
  skipped_count int not null default 0,
  total_score numeric,                -- correct*marks_per_correct - wrong*negative_marks_per_wrong
  started_at timestamptz not null,
  completed_at timestamptz,
  duration_seconds int
);

-- One row per question answered (or skipped) within an attempt.
create table attempt_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid references attempts(id) on delete cascade,
  question_id uuid references questions(id),
  selected_answer int,             -- null when skipped
  status text check (status in ('correct','incorrect','skipped')) not null,
  time_taken_seconds int,
  answered_at timestamptz default now()
);

-- Helpful indexes for the analytics queries in docs/PRD.md section 6.
create index idx_question_sets_folder_id on question_sets(folder_id);
create index idx_questions_question_set_id on questions(question_set_id);
create index idx_attempts_question_set_id on attempts(question_set_id);
create index idx_attempt_answers_attempt_id on attempt_answers(attempt_id);
create index idx_attempt_answers_question_id on attempt_answers(question_id);

-- RLS is enabled (Supabase flags tables without it), but the app has no
-- auth layer yet — it's a single-user personal tool accessed with the
-- project's anon/publishable key (see docs/PRD.md section 8 and the "Auth"
-- open decision in docs/IMPLEMENTATION_PLAN.md). These policies are
-- intentionally permissive to match that; scope them to auth.uid() if
-- multi-user auth is ever added.
alter table folders enable row level security;
alter table question_sets enable row level security;
alter table questions enable row level security;
alter table attempts enable row level security;
alter table attempt_answers enable row level security;

create policy "allow all - folders" on folders for all using (true) with check (true);
create policy "allow all - question_sets" on question_sets for all using (true) with check (true);
create policy "allow all - questions" on questions for all using (true) with check (true);
create policy "allow all - attempts" on attempts for all using (true) with check (true);
create policy "allow all - attempt_answers" on attempt_answers for all using (true) with check (true);

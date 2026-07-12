-- Fixes deleting a question failing (foreign-key violation) once it has been
-- answered at least once — attempt_answers.question_id had no delete action,
-- unlike attempt_answers.attempt_id which already cascades. Matches the
-- "Manage Questions" screen's own copy ("This also removes any recorded
-- answers for it.").
-- Run this once against your existing Supabase project (SQL editor or
-- `supabase db execute`) — schema.sql alone only affects fresh databases.

alter table attempt_answers drop constraint if exists attempt_answers_question_id_fkey;
alter table attempt_answers
  add constraint attempt_answers_question_id_fkey
  foreign key (question_id) references questions(id) on delete cascade;

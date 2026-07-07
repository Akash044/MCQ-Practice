# MCQ Practice

A personal exam-practice app: import MCQ question sets from JSON, take timed or untimed exams, and track performance over time — with a focus on resurfacing and drilling questions you get wrong repeatedly.

Built with Flutter + [forui](https://forui.dev) for UI, [Riverpod](https://riverpod.dev) for state, and [Supabase](https://supabase.com) (Postgres + REST) as the backend.

See [docs/PRD.md](docs/PRD.md) for the full product spec and [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) for what's built so far and what's left.

## Getting started

1. Create a Supabase project, then run [supabase/schema.sql](supabase/schema.sql) in its SQL editor.
2. Copy `.env.example` to `.env` and fill in `SUPABASE_URL` / `SUPABASE_ANON_KEY` from your project's API settings.
3. `flutter pub get`
4. `flutter run`

## Features

- Folder-organized question sets, imported from JSON with per-question validation
- Practice mode (instant feedback) and test mode, with optional negative marking, exam/per-question timers, and question/option shuffling
- Wrong-answer and skipped-question retry pools with an automatic mastery rule (2 consecutive correct answers to graduate a question out of the pool)
- Progress dashboard: accuracy trend, per-topic breakdown, persistent weak spots, streaks
- Offline-tolerant: cached question sets for retaking without a connection, with a local sync queue for attempts submitted while offline

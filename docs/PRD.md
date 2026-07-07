# Product Requirements Document: MCQ Exam & Progress Tracker

## 1. Overview

A personal exam-practice app that ingests MCQ question sets from a JSON file, lets the user take timed/untimed exams, and tracks performance over time — with a specific focus on surfacing and drilling questions the user gets wrong repeatedly.

**Stack:** Flutter (mobile app) + Supabase (Postgres + Auth) as backend/data store.

## 1.1 Flutter-Specific Technical Notes

- **Supabase integration:** `supabase_flutter` package for auth, database queries, and realtime (not strictly needed here, but available if you want live sync across devices later).
- **JSON import:** `file_picker` package to let the user select a `.json` file from device storage; parse with Dart's built-in `dart:convert` (`jsonDecode`), then validate against the schema in §4 before inserting into Supabase.
- **Local/offline support:** since exams should be takeable offline, cache the active question set and in-progress attempt locally (e.g. `sqflite` or `Hive`) and sync completed attempts to Supabase once connectivity returns. A simple "pending sync" queue table locally is enough — no need for full offline-first architecture.
- **Timers:** implement with Dart's `Timer.periodic` or a package like `easy_stopwatch`; must handle app lifecycle events (`AppLifecycleState.paused/resumed`) so an in-progress timer doesn't silently lose or gain time if the user backgrounds the app.
- **State management:** Riverpod — chosen for clean async handling (Supabase calls, offline sync queue), no `BuildContext` dependency (needed for timer callbacks updating state), and easier testing of scoring/mastery logic in isolation.
- **Charts (progress dashboard):** `fl_chart` or `syncfusion_flutter_charts` are common Flutter choices for the accuracy-trend line chart and topic breakdown.

## 2. Goals

- Parse a user-supplied JSON file of MCQs and load it into the app.
- Take an exam session with instant or end-of-exam scoring.
- Persist every attempt so progress can be tracked across sessions.
- Identify and resurface wrong answers for targeted review/re-testing.
- Show improvement trends over time (accuracy %, weak topics, streaks).

## 3. Non-Goals (v1)

- Multi-user / collaborative exams (this is single-user, personal use).
- Question authoring UI (questions come from JSON only, not manually typed in-app).
- Adaptive difficulty algorithms (spaced repetition can be a v2 stretch goal).

## 4. JSON Input Format (proposed — confirm/adjust when you share your actual file)

Since you'll supply the exact format, here's a proposed schema to align on. Flag any deltas from your real file and I'll adjust the parser design accordingly.

```json
{
  "exam_title": "Fluid Dynamics - Chapter 3",
  "subject": "Fluid Dynamics",
  "questions": [
    {
      "id": "q1",
      "question": "What is the SI unit of dynamic viscosity?",
      "options": ["Pa", "Pa·s", "N/m", "m²/s"],
      "correct_answer": 1,
      "explanation": "Dynamic viscosity is measured in Pascal-seconds (Pa·s).",
      "topic": "Viscosity",
      "difficulty": "medium"
    }
  ]
}
```

Fields `explanation`, `topic`, `difficulty` are optional but strongly recommended — `topic` in particular drives the weak-area analytics in section 6.3.

## 5. Core Features

### 5.0 Folder Organization
- User creates folders to group question sets by subject/exam type — e.g. `"BCS Model Test"`, `"Bangladesh Affairs"`.
- Each imported JSON file (question set) gets assigned to a folder at import time.
- Folders support nesting (e.g. `BCS Preliminary > Bangla > Model Tests`), though flat folders are enough for v1 use.
- Browsing flow: folder list → sets inside folder → pick a set → configure and start an exam.
- Import flow lets you pick an existing folder or create a new one on the fly.

### 5.1 JSON Import
- Upload/select a `.json` file, assign it to a folder.
- Validate structure (required fields present, `correct_answer` index in range, no duplicate `id`s).
- On successful validation, upsert into Supabase (`question_sets` + `questions` tables — see §6).
- On validation failure, show which questions failed and why (don't silently drop them).

### 5.2 Exam Session
- Choose a question set (or a filtered subset: by topic, by difficulty, "only wrong answers," or "only skipped questions" — see 5.2.1).
- Choose mode: **Practice** (instant feedback + explanation after each answer) or **Test** (no feedback until the end).
- Randomize question order and option order per session (toggle-able).
- **Retake anytime** — the same question set can be attempted as many times as you like; every attempt is stored as its own row, so history and trends are never overwritten.
- On submit, score the session (see 5.2.2 for negative marking) and save the full attempt (every question + selected answer or skip + correctness) to Supabase.

#### 5.2.1 Retry Pools
Two dedicated ways to start a session from a subset instead of the full set:
- **Retry Wrong Answers** — pulls every question currently marked incorrect (not yet "mastered," see 5.5) from a chosen set, or across all sets in a folder.
- **Retry Skipped** — pulls every question left unanswered in past attempts, so nothing gets permanently lost just because you ran out of time or intentionally skipped it.
- Both pools can be combined with topic/difficulty filters too.

#### 5.2.2 Negative Marking
- Each question set has a default scoring scheme, editable per attempt before you start:
  - `marks_per_correct` (default: 1)
  - `negative_marks_per_wrong` (default: 0 — set to e.g. 0.25 or 0.5 to match real exam negative-marking rules)
  - Skipped questions always score 0 (no penalty for skipping).
- Final score = `(correct_count × marks_per_correct) − (wrong_count × negative_marks_per_wrong)`.
- Since scoring is chosen per attempt, you can practice the same set once with no negative marking and again with real exam-style negative marking.

#### 5.2.3 Timers
- **Exam timer** — optional overall countdown for the whole session (e.g. 200 questions in 180 minutes), auto-submits at zero.
- **Per-question timer** — optional countdown per question (e.g. 45 seconds each); if it runs out, that question is recorded as skipped and the app auto-advances.
- Both are independent toggles set at attempt start — leave both off for untimed practice, use one or both to simulate real exam pressure.

### 5.3 Results & Review
- Immediate results screen: score (with negative marking applied if enabled), time taken, list of questions with your answer vs. correct answer vs. skipped, + explanation.
- "Retry Wrong Answers" and "Retry Skipped" buttons to instantly spin up a new session from just those questions.

### 5.4 Progress Tracking
- History of all past attempts (date, question set, score, duration).
- Accuracy trend chart over time (overall, and per topic if `topic` is present).
- "Persistent weak spots" view: questions/topics with a wrong-answer rate above some threshold across all attempts, sorted worst-first.
- Streaks / consistency (e.g., days practiced, current streak).

### 5.5 Wrong-Answer Tracking (core differentiator)
- Every incorrect answer is logged with: question, chosen option, correct option, timestamp, exam session.
- A question is "mastered" only after N consecutive correct attempts (configurable, default 2) — until then it stays in the review pool.
- Dedicated "Wrong Answer Bank" screen, filterable by topic/difficulty, usable to build custom retry exams.

## 6. Data Model (Supabase / Postgres)

```sql
-- Organizing structure: "BCS Model Test", "Bangladesh Affairs", etc.
-- parent_id is self-referencing so folders can nest if you want that later
create table folders (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  parent_id uuid references folders(id) on delete cascade,
  created_at timestamptz default now()
);

-- One row per imported JSON file, belongs to a folder
create table question_sets (
  id uuid primary key default gen_random_uuid(),
  folder_id uuid references folders(id) on delete cascade,
  title text not null,              -- from "exam_title" in the JSON
  subject text,                     -- from "subject" in the JSON
  default_marks_per_correct numeric default 1,
  default_negative_marks_per_wrong numeric default 0,
  created_at timestamptz default now()
);

-- One row per question
create table questions (
  id uuid primary key default gen_random_uuid(),
  question_set_id uuid references question_sets(id) on delete cascade,
  source_id text,              -- the "id" from the JSON, for traceability
  question_text text not null,
  options jsonb not null,       -- array of option strings
  correct_answer int not null,  -- index into options
  explanation text,
  topic text,
  difficulty text,
  created_at timestamptz default now()
);

-- One row per exam session taken (a set can be attempted any number of times)
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

-- One row per question answered (or skipped) within an attempt
create table attempt_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid references attempts(id) on delete cascade,
  question_id uuid references questions(id),
  selected_answer int,             -- null when skipped
  status text check (status in ('correct','incorrect','skipped')) not null,
  time_taken_seconds int,
  answered_at timestamptz default now()
);
```

**Derived views (for analytics, no extra tables needed):**
- Per-question wrong rate: `count(status='incorrect') / count(*)` grouped by `question_id`.
- Per-topic accuracy: join `attempt_answers` → `questions`, group by `topic` — **only from attempts where `source_type` is `full_set` or `custom`** (retry sessions excluded, per §9).
- Mastery status: a question exits the wrong-answer pool once its last N `attempt_answers` (any source_type, excluding skips) are all `status = 'correct'`, N = 2 by default.
- Current wrong-answer pool: questions whose most recent non-skipped attempt has `status = 'incorrect'` and are not yet "mastered."
- Current skipped pool: questions whose most recent attempt has `status = 'skipped'`.
- Progress trend chart data: score/accuracy over time, filtered to `source_type in ('full_set','custom')` only.

## 7. Key User Flows

1. **Organize** → create folders (e.g. "BCS Model Test", "Bangladesh Affairs").
2. **Import** → upload JSON → validate → assign to folder → confirm → stored in Supabase.
3. **Start Exam** → pick set → choose full set / wrong-answers-only / skipped-only → set mode, timers, negative marking → answer → submit → see results.
4. **Retake** → same set, any number of times, each saved as a distinct attempt.
5. **Review Mistakes** → open Wrong Answer Bank or Skipped Bank → optionally start a retry session directly from there.
6. **Check Progress** → dashboard with accuracy trend, topic breakdown, weak-spot list, score history across all attempts of a set.

## 8. Non-Functional Requirements

- Works fully offline for taking an exam once questions are loaded locally (optional, but nice for a personal tool) — sync attempts to Supabase when back online.
- JSON files could be large (hundreds of questions); import/validation should not block the UI.
- All personal data stays in your own Supabase project — no multi-tenant concerns needed for v1.
- Timer logic (exam-level and per-question) must survive app backgrounding/refresh without losing elapsed time, if this will run in a browser tab or mobile app that can be interrupted.

## 9. Resolved Decisions

- **Per-question timeout** → logged as `skipped`, not `incorrect`. No penalty, just goes into the skipped pool for later retry.
- **Mastery rule** → automatic. A question is removed from the wrong-answer bank once it's been answered correctly N times in a row (default N = 2, configurable later if needed).
- **Retry attempts vs. original attempts** → tracked **separately**. `attempts.source_type` (`wrong_answers_retry` / `skipped_retry`) is excluded from the main accuracy/progress-trend analytics — those charts only reflect `full_set` (and `custom`) attempts, so retry drilling doesn't artificially inflate your "improvement" stats. Retry attempts still count toward the mastery streak (N correct in a row) — that's their whole purpose — they're just excluded from the trend charts.

## 10. Remaining Open Question

- Any interest in exporting progress data (CSV) later, or is in-app viewing enough?

## 11. Suggested v2 Ideas (not in scope now)

- Spaced repetition scheduling (e.g., SM-2) for the wrong-answer bank instead of simple streak-based mastery.
- Multiple JSON sets combined into one "master" exam pool.
- Bookmarking/flagging questions during an exam for later review regardless of correctness.

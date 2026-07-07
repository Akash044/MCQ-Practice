# Implementation Plan & Progress

Companion to [PRD.md](./PRD.md). Tracks the build order and what's done so a future session can pick up without re-deriving context. Update the checkboxes as work lands.

## Phase 0 — Project scaffolding
- [x] `flutter create` project at repo root (org: `com.mcqtest`, name: `mcq_test`)
- [x] `docs/PRD.md` — full requirements doc
- [x] `supabase/schema.sql` — Postgres schema (folders, question_sets, questions, attempts, attempt_answers)
- [x] Add dependencies to `pubspec.yaml`: `supabase_flutter`, `flutter_riverpod`, `file_picker`, `sqflite`, `fl_chart`, `uuid`, `connectivity_plus`, `flutter_dotenv`
- [x] `.env` / `.env.example` wiring for `SUPABASE_URL` / `SUPABASE_ANON_KEY` (git-ignored), loaded in `lib/main.dart` via `flutter_dotenv`, client bootstrapped via `Supabase.initialize`
- [x] `lib/` folder structure: `models/`, `services/`, `providers/`, `screens/`, `widgets/`, `utils/`
- [ ] **You still need to:** create the actual Supabase project, run `supabase/schema.sql` against it, and put the real URL/anon (publishable) key into `.env` — currently placeholder values, app will fail to connect until this is done

## Phase 1 — Data layer
- [x] Dart models mirroring schema: `Folder`, `QuestionSet`, `Question`, `Attempt`, `AttemptAnswer` (`lib/models/`)
- [x] JSON import: file picker → `jsonDecode` → schema validation (`lib/utils/question_set_validator.dart`, §4/§5.1 of PRD: required fields, `correct_answer` range check, duplicate `id` check) → surfaced per-question errors on failure (`lib/screens/import/import_screen.dart`)
- [x] Supabase service layer (`lib/services/supabase_service.dart`): CRUD for folders/question_sets/questions, insert attempts + attempt_answers, fetch answers for wrong/skipped pool derivation
- [ ] Local cache (sqflite): active question set + in-progress attempt for offline play; a simple pending-sync queue table for completed attempts made offline — **not started**, `sqflite` dependency is added but unused so far

## Phase 2 — Exam session
- [x] Folder browser (`lib/screens/folders/folder_list_screen.dart`) → set list (`question_set_list_screen.dart`) → import screen wired end-to-end
- [x] Exam setup screen (`lib/screens/exam/exam_setup_screen.dart`): mode (practice/test), source (full set / wrong-answers retry / skipped retry, via `lib/utils/mastery.dart`), topic + difficulty filters (`FSelect`), marks-per-correct / negative-marks overrides, exam + per-question timer toggles, question/option shuffle toggles
- [x] Question runner screen (`lib/screens/exam/exam_runner_screen.dart`): option shuffle via per-question `optionOrder` permutation (avoids remapping `correct_answer`), practice-mode instant feedback + explanation (`FAlert`), test-mode silent scoring, confirm-before-leaving via `PopScope`
- [x] Exam-level countdown timer + per-question countdown timer (`lib/providers/exam_session_notifier.dart`) — implemented as **wall-clock deadlines** (`examEndTime`/`questionEndTime` `DateTime`s), not decremented counters, so `AppLifecycleState.paused/resumed` can't cause drift: a 1s `Timer.periodic` just re-reads `DateTime.now()` against the deadline. `ExamSessionNotifier.handleLifecycle()` cancels the ticker on pause and immediately reconciles + restarts on resume (catches an expiry that happened while backgrounded).
- [x] Submit flow: `ExamSessionState.totalScore`/`correctCount`/`wrongCount`/`skippedCount` computed per §5.2.2 from recorded answers; `ExamRunnerScreen._finish()` persists `attempts` + `attempt_answers` via `SupabaseService`, degrading gracefully (toast + still shows results locally) if the save fails — this is the gap Phase 5's offline queue is meant to close
- [ ] Not done: per-question `time_taken_seconds` is wall-clock elapsed while that question was on screen (simple, not pause-aware if user backgrounds mid-question — acceptable for v1, revisit if it matters)

## Phase 3 — Results & retry pools
- [x] Results screen (`lib/screens/results/results_screen.dart`): score, correct/wrong/skipped counts, total time, per-question your-answer vs. correct-answer vs. skipped + explanation (via `FCard` per question)
- [ ] "Retry Wrong Answers" / "Retry Skipped" buttons *from the results screen* — not added; today you retry by going back to the set and picking the source in exam setup (which already supports it). Revisit if one-tap retry from results is worth the duplication.
- [ ] Wrong Answer Bank screen (filterable by topic/difficulty) driving custom retry exams — pool derivation logic already exists in `lib/utils/mastery.dart` (`QuestionPools.wrongPool`/`skippedPool`), just needs a dedicated browsing screen
- [ ] Skipped Bank screen (same note as above)

## Phase 4 — Progress dashboard
- [ ] Attempt history list (date, set, score, duration)
- [ ] Accuracy trend chart (fl_chart), filtered to `source_type in ('full_set','custom')` per §9
- [ ] Per-topic accuracy breakdown
- [ ] Persistent weak-spots view (wrong-rate threshold, worst-first)
- [x] Mastery computation (last N=2 consecutive correct `attempt_answers`, any source_type, excluding skips) — `QuestionPools.isMastered`/`wrongPool`/`skippedPool` in `lib/utils/mastery.dart`, already wired into exam setup's source picker; still needs a UI surface for browsing (see Wrong/Skipped Bank screens in Phase 3)
- [ ] Streak / consistency tracking

## Phase 5 — Polish
- [ ] Offline sync: flush pending-sync queue when connectivity returns (`connectivity_plus`)
- [ ] Background import validation (isolate/compute) so large JSON files don't block UI
- [ ] Empty/error states across screens

## Open decisions (revisit with user)
- CSV export of progress data — deferred per PRD §10, not yet decided.
- Auth: PRD assumes single-user/personal use against the developer's own Supabase project — confirm whether Supabase Auth (even anonymous/email) is needed or if this stays keyless/local-only for v1.

## UI library

- Using [forui](https://forui.dev) (`^0.21.3` — the version that resolves against this project's Flutter 3.41.9 SDK; latest is 0.23.0 but requires Flutter 3.44+) for all widgets instead of Material. Screens use `FScaffold`/`FHeader`/`FTileGroup`/`FTile`/`FButton`/`FTextField`/`FAlert`/`FDialog` (via `showFDialog`)/`FToaster` (via `showFToast`) — see `lib/screens/` for patterns to copy.
- `lib/main.dart` still uses `MaterialApp` as the navigation root (for `MaterialPageRoute`/`Navigator`) but wraps its `builder` in `FTheme` + `FToaster` so forui widgets and toasts work anywhere in the tree. `FThemes.zinc.light.touch` is the active theme — `FThemes.<palette>.<brightness>` returns an `FPlatformThemeData`, pick `.touch` or `.desktop` off of it to get an actual `FThemeData`.
- Icons come from `FIcons` (Lucide icon set bundled via `forui_assets`, re-exported by `package:forui/forui.dart`) — don't add a separate icon package.
- If bumping forui later, re-check `FHeader`/`FTile`/`FButton`/`FTextField` constructor signatures against the installed version's source in the pub cache before assuming the API — this library's API has been shifting release to release (e.g. `anonKey`→`publishableKey`-style renames happen here too).

## Notes for whoever resumes this
- Schema, mastery rule, and analytics filtering logic are spec'd in PRD §6 and §9 — don't re-derive, just implement against them.
- Riverpod chosen specifically for `BuildContext`-free timer callbacks — keep timer state in a provider, not a `StatefulWidget`, to preserve that benefit.
- `flutter analyze` is clean as of this session (0 issues). Keep it that way — run it after each phase.
- `supabase_flutter` 2.16 deprecated `anonKey` in favor of `publishableKey` on `Supabase.initialize` — already using the new name in `lib/main.dart`, don't revert.
- `test/widget_test.dart` is a placeholder; the default counter test was removed since it referenced the deleted boilerplate `MyApp`/`MyHomePage`. Real widget tests need a mocked Supabase client since `main()` calls `Supabase.initialize()` before `runApp()`.
- Windows desktop builds need Developer Mode enabled (`start ms-settings:developers`) for plugin symlink support — surfaced as a warning during `flutter pub get`, not yet resolved on this machine.

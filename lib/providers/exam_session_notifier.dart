import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/exam_config.dart';
import '../models/exam_session.dart';
import '../models/question.dart';

/// Drives a single exam session: question order, answer recording, and the
/// exam-level / per-question countdowns from docs/PRD.md section 5.2.3.
///
/// Timers are wall-clock deadlines (`examEndTime`/`questionEndTime`), not
/// decremented counters. A 1s [Timer.periodic] just re-reads `DateTime.now()`
/// against those deadlines, so if the OS suspends the ticker while the app is
/// backgrounded, resuming recomputes the correct remaining time instead of
/// drifting — satisfying the "timer must survive backgrounding" requirement
/// in section 8 without needing to track paused duration separately.
class ExamSessionNotifier extends StateNotifier<ExamSessionState?> {
  ExamSessionNotifier() : super(null);

  Timer? _ticker;
  DateTime _currentQuestionEnteredAt = DateTime.now();

  void start({required List<Question> questions, required ExamConfig config}) {
    final ordered = config.shuffleQuestions
        ? (List.of(questions)..shuffle())
        : questions;
    final now = DateTime.now();
    final runnerQuestions = [
      for (final q in ordered)
        RunnerQuestion(
          question: q,
          optionOrder: config.shuffleOptions
              ? (List.generate(q.options.length, (i) => i)..shuffle())
              : List.generate(q.options.length, (i) => i),
        ),
    ];

    _currentQuestionEnteredAt = now;
    state = ExamSessionState(
      config: config,
      questions: runnerQuestions,
      currentIndex: 0,
      startedAt: now,
      examEndTime: config.examTimerMinutes != null
          ? now.add(Duration(minutes: config.examTimerMinutes!))
          : null,
      questionEndTime: config.perQuestionTimerSeconds != null
          ? now.add(Duration(seconds: config.perQuestionTimerSeconds!))
          : null,
    );
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    final s = state;
    if (s == null ||
        (s.config.examTimerMinutes == null &&
            s.config.perQuestionTimerSeconds == null)) {
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final s = state;
    if (s == null || s.submitted) return;
    final now = DateTime.now();
    if (s.examEndTime != null && !now.isBefore(s.examEndTime!)) {
      submit();
      return;
    }
    if (s.questionEndTime != null && !now.isBefore(s.questionEndTime!)) {
      _advance();
      return;
    }
    // No field actually changes, but this forces a rebuild so the widget's
    // computed `examRemaining`/`questionRemaining` getters re-read the clock.
    state = s.copyWith();
  }

  /// Call from the runner screen's `didChangeAppLifecycleState`. Cancels the
  /// ticker while backgrounded and reconciles + restarts it on resume, so a
  /// timer expiry that happened while backgrounded is caught immediately.
  void handleLifecycle(AppLifecycleState lifecycleState) {
    switch (lifecycleState) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _ticker?.cancel();
      case AppLifecycleState.resumed:
        _tick();
        _startTicker();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void selectAnswer(int originalIndex) {
    final s = state;
    if (s == null || s.submitted) return;
    final updated = [...s.questions];
    updated[s.currentIndex] = updated[s.currentIndex].copyWith(
      selectedOriginalIndex: originalIndex,
    );
    state = s.copyWith(questions: updated);
  }

  void next() => _advance();

  void previous() {
    final s = state;
    if (s == null || s.currentIndex == 0) return;
    _recordTimeTaken(s);
    final afterRecord = state!;
    _currentQuestionEnteredAt = DateTime.now();
    state = afterRecord.copyWith(
      currentIndex: afterRecord.currentIndex - 1,
      questionEndTime: afterRecord.config.perQuestionTimerSeconds != null
          ? DateTime.now().add(
              Duration(seconds: afterRecord.config.perQuestionTimerSeconds!),
            )
          : null,
      clearQuestionEndTime: afterRecord.config.perQuestionTimerSeconds == null,
    );
  }

  void _advance() {
    final s = state;
    if (s == null) return;
    _recordTimeTaken(s);
    final afterRecord = state!;

    if (afterRecord.currentIndex >= afterRecord.questions.length - 1) {
      submit();
      return;
    }

    _currentQuestionEnteredAt = DateTime.now();
    state = afterRecord.copyWith(
      currentIndex: afterRecord.currentIndex + 1,
      questionEndTime: afterRecord.config.perQuestionTimerSeconds != null
          ? DateTime.now().add(
              Duration(seconds: afterRecord.config.perQuestionTimerSeconds!),
            )
          : null,
      clearQuestionEndTime: afterRecord.config.perQuestionTimerSeconds == null,
    );
  }

  void _recordTimeTaken(ExamSessionState s) {
    final elapsed = DateTime.now()
        .difference(_currentQuestionEnteredAt)
        .inSeconds;
    final updated = [...s.questions];
    updated[s.currentIndex] = updated[s.currentIndex].copyWith(
      timeTakenSeconds: elapsed,
    );
    state = s.copyWith(questions: updated);
  }

  void submit() {
    final s = state;
    if (s == null || s.submitted) return;
    _recordTimeTaken(s);
    _ticker?.cancel();
    state = state!.copyWith(submitted: true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

// Deliberately not .autoDispose: ExamSetupScreen only ever does a one-off
// `ref.read(examSessionProvider.notifier).start(...)` — nothing watches the
// provider until the runner screen mounts a moment later via
// pushReplacement. An autoDispose provider with zero active watchers gets
// disposed on the next microtask, which raced with that navigation and
// reset the session to null before the runner screen ever saw it (visible
// as a stuck loading spinner). Kept alive for the app's lifetime instead;
// each new exam just overwrites the state via `start()`.
final examSessionProvider =
    StateNotifierProvider<ExamSessionNotifier, ExamSessionState?>(
      (ref) => ExamSessionNotifier(),
    );

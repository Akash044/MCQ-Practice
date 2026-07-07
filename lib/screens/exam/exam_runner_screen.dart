import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/attempt.dart';
import '../../models/attempt_answer.dart';
import '../../models/exam_session.dart';
import '../../models/folder.dart';
import '../../models/question_set.dart';
import '../../providers/exam_session_notifier.dart';
import '../../providers/supabase_providers.dart';
import '../../services/local_db.dart';
import '../results/results_screen.dart';

String _formatDuration(Duration d) {
  final clamped = d.isNegative ? Duration.zero : d;
  final minutes = clamped.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = clamped.inSeconds.remainder(60).toString().padLeft(2, '0');
  return clamped.inHours > 0 ? '${clamped.inHours}:$minutes:$seconds' : '$minutes:$seconds';
}

class ExamRunnerScreen extends ConsumerStatefulWidget {
  const ExamRunnerScreen({super.key, required this.folder, required this.questionSet});

  final Folder folder;
  final QuestionSet questionSet;

  @override
  ConsumerState<ExamRunnerScreen> createState() => _ExamRunnerScreenState();
}

class _ExamRunnerScreenState extends ConsumerState<ExamRunnerScreen> with WidgetsBindingObserver {
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(examSessionProvider.notifier).handleLifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<bool> _confirmExit() async {
    final leave = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        title: const Text('Leave exam?'),
        body: const Text('Your progress in this attempt will be lost.'),
        actions: [
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          FButton(
            variant: FButtonVariant.destructive,
            onPress: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Map<String, dynamic> _answerInsertMap(RunnerQuestion rq) {
    final status = !rq.isAnswered
        ? AnswerStatus.skipped
        : (rq.isCorrect ? AnswerStatus.correct : AnswerStatus.incorrect);
    return {
      'question_id': rq.question.id,
      if (rq.selectedOriginalIndex != null) 'selected_answer': rq.selectedOriginalIndex,
      'status': status.value,
      if (rq.timeTakenSeconds != null) 'time_taken_seconds': rq.timeTakenSeconds,
    };
  }

  Future<void> _finish(ExamSessionState session) async {
    if (_finishing) return;
    _finishing = true;

    final service = ref.read(supabaseServiceProvider);
    final attemptInsertMap = Attempt(
      id: '',
      questionSetId: widget.questionSet.id,
      sourceType: session.config.sourceType,
      mode: session.config.mode,
      marksPerCorrect: session.config.marksPerCorrect,
      negativeMarksPerWrong: session.config.negativeMarksPerWrong,
      examTimerMinutes: session.config.examTimerMinutes,
      perQuestionTimerSeconds: session.config.perQuestionTimerSeconds,
      totalQuestions: session.questions.length,
      correctCount: session.correctCount,
      wrongCount: session.wrongCount,
      skippedCount: session.skippedCount,
      totalScore: session.totalScore,
      startedAt: session.startedAt,
      completedAt: DateTime.now(),
      durationSeconds: DateTime.now().difference(session.startedAt).inSeconds,
    ).toInsertMap();
    final answerInsertMaps = [for (final rq in session.questions) _answerInsertMap(rq)];

    Attempt? saved;
    var queued = false;
    try {
      final savedRow = await service.insertAttemptRaw(attemptInsertMap);
      saved = Attempt.fromMap(savedRow);
      await service.insertAttemptAnswersRaw([
        for (final a in answerInsertMaps) {...a, 'attempt_id': saved.id},
      ]);
    } catch (e) {
      try {
        await LocalDb.enqueuePendingAttempt(attemptInsertMap, answerInsertMaps);
        queued = true;
      } catch (_) {
        // Local disk write also failed — nothing more we can do; the toast
        // below reports the original network/server error.
      }
      if (mounted) {
        showFToast(
          context: context,
          variant: queued ? FToastVariant.primary : FToastVariant.destructive,
          title: Text(queued ? 'Saved locally' : 'Could not save this attempt'),
          description: Text(
            queued
                ? "You're offline — this will sync automatically once you're back online."
                : '$e',
          ),
        );
      }
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ResultsScreen(
          folder: widget.folder,
          questionSet: widget.questionSet,
          session: session,
          savedAttempt: saved,
          queuedForSync: queued,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ExamSessionState?>(examSessionProvider, (previous, next) {
      if (next != null && next.submitted && previous?.submitted != true) {
        _finish(next);
      }
    });

    final session = ref.watch(examSessionProvider);
    if (session == null || session.submitted) {
      return const FScaffold(child: Center(child: FCircularProgress()));
    }

    final notifier = ref.read(examSessionProvider.notifier);
    final current = session.current;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmExit() && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: FScaffold(
        header: FHeader.nested(
          title: Text('Question ${session.currentIndex + 1} / ${session.questions.length}'),
          prefixes: [
            FHeaderAction.back(onPress: () async {
              if (await _confirmExit()) {
                if (context.mounted) Navigator.pop(context);
              }
            }),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (session.examRemaining != null || session.questionRemaining != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (session.examRemaining != null)
                    FBadge(child: Text('Exam: ${_formatDuration(session.examRemaining!)}')),
                  if (session.questionRemaining != null)
                    FBadge(
                      variant: session.questionRemaining!.inSeconds <= 5
                          ? FBadgeVariant.destructive
                          : FBadgeVariant.secondary,
                      child: Text('Question: ${_formatDuration(session.questionRemaining!)}'),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            Text(current.question.questionText),
            const SizedBox(height: 12),
            Expanded(
              child: FTileGroup(
                children: [
                  for (final originalIndex in current.optionOrder)
                    FTile(
                      title: Text(current.question.options[originalIndex]),
                      selected: current.selectedOriginalIndex == originalIndex,
                      suffix: session.config.mode != AttemptMode.practice || !current.isAnswered
                          ? null
                          : originalIndex == current.question.correctAnswer
                              ? const Icon(FIcons.circleCheck)
                              : (originalIndex == current.selectedOriginalIndex
                                  ? const Icon(FIcons.circleX)
                                  : null),
                      onPress: session.config.mode == AttemptMode.practice && current.isAnswered
                          ? null
                          : () => notifier.selectAnswer(originalIndex),
                    ),
                ],
              ),
            ),
            if (session.config.mode == AttemptMode.practice && current.isAnswered) ...[
              const SizedBox(height: 8),
              FAlert(
                variant: current.isCorrect ? FAlertVariant.primary : FAlertVariant.destructive,
                title: Text(current.isCorrect ? 'Correct' : 'Incorrect'),
                subtitle: current.question.explanation != null ? Text(current.question.explanation!) : null,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (session.currentIndex > 0)
                  Expanded(
                    child: FButton(
                      variant: FButtonVariant.outline,
                      onPress: notifier.previous,
                      child: const Text('Previous'),
                    ),
                  ),
                if (session.currentIndex > 0) const SizedBox(width: 12),
                Expanded(
                  child: FButton(
                    onPress: notifier.next,
                    child: Text(session.isLast ? 'Submit' : (current.isAnswered ? 'Next' : 'Skip')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

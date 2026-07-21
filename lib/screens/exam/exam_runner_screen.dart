import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/attempt.dart';
import '../../models/attempt_answer.dart';
import '../../models/exam_session.dart';
import '../../models/folder.dart';
import '../../models/question_set.dart';
import '../../providers/exam_providers.dart';
import '../../providers/exam_session_notifier.dart';
import '../../providers/supabase_providers.dart';
import '../../services/local_db.dart';
import '../results/results_screen.dart';

const _correctColor = Color(0xFF16A34A);
const _incorrectColor = Color(0xFFDC2626);

String _formatDuration(Duration d) {
  final clamped = d.isNegative ? Duration.zero : d;
  final minutes = clamped.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = clamped.inSeconds.remainder(60).toString().padLeft(2, '0');
  return clamped.inHours > 0
      ? '${clamped.inHours}:$minutes:$seconds'
      : '$minutes:$seconds';
}

class ExamRunnerScreen extends ConsumerStatefulWidget {
  const ExamRunnerScreen({
    super.key,
    required this.folder,
    required this.questionSet,
  });

  final Folder folder;
  final QuestionSet questionSet;

  @override
  ConsumerState<ExamRunnerScreen> createState() => _ExamRunnerScreenState();
}

class _ExamRunnerScreenState extends ConsumerState<ExamRunnerScreen>
    with WidgetsBindingObserver {
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

  Future<void> _confirmSubmitEarly(ExamSessionState session) async {
    final answered = session.correctCount + session.wrongCount;
    final remaining = session.questions.length - answered;
    final submit = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        title: const Text('Submit exam now?'),
        body: Text(
          '$answered of ${session.questions.length} questions answered. '
          '$remaining question${remaining == 1 ? '' : 's'} will be marked skipped. '
          "This can't be undone.",
        ),
        actions: [
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          FButton(
            onPress: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (submit ?? false) {
      ref.read(examSessionProvider.notifier).submit();
    }
  }

  Map<String, dynamic> _answerInsertMap(RunnerQuestion rq) {
    final status = !rq.isAnswered
        ? AnswerStatus.skipped
        : (rq.isCorrect ? AnswerStatus.correct : AnswerStatus.incorrect);
    return {
      'question_id': rq.question.id,
      if (rq.selectedOriginalIndex != null)
        'selected_answer': rq.selectedOriginalIndex,
      'status': status.value,
      if (rq.timeTakenSeconds != null)
        'time_taken_seconds': rq.timeTakenSeconds,
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
    final answerInsertMaps = [
      for (final rq in session.questions) _answerInsertMap(rq),
    ];

    Attempt? saved;
    var queued = false;
    try {
      final savedRow = await service.insertAttemptRaw(attemptInsertMap);
      saved = Attempt.fromMap(savedRow);
      await service.insertAttemptAnswersRaw([
        for (final a in answerInsertMaps) {...a, 'attempt_id': saved.id},
      ]);
      // Both providers are plain (non-autoDispose) FutureProviders that cache
      // their result indefinitely — without this, the just-finished attempt
      // is invisible to ProgressScreen's history list and to the wrong/
      // skipped pools ExamSetupScreen computes for "retry" flows, since both
      // would still be serving the pre-attempt cached data.
      ref.invalidate(answersForSetProvider(widget.questionSet.id));
      ref.invalidate(attemptHistoryProvider(widget.questionSet.id));
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

  FTile _buildOption(
    ExamSessionState session,
    RunnerQuestion current,
    ExamSessionNotifier notifier,
    int originalIndex,
  ) {
    final revealed =
        session.config.mode == AttemptMode.practice && current.isAnswered;
    final isCorrectOption = originalIndex == current.question.correctAnswer;
    final isSelected = originalIndex == current.selectedOriginalIndex;

    Color? feedbackColor;
    if (revealed && isCorrectOption) {
      feedbackColor = _correctColor;
    } else if (revealed && isSelected) {
      feedbackColor = _incorrectColor;
    } else if (isSelected) {
      // Test mode never reveals correct/incorrect, and even practice mode
      // is unrevealed for one frame before `isAnswered` flips true — either
      // way, FTile's built-in `selected` styling alone was too subtle to
      // tell at a glance whether an option was actually picked.
      feedbackColor = context.theme.colors.primary;
    }

    return FTile(
      style: feedbackColor == null
          ? const FItemStyleDelta.context()
          : FItemStyleDelta.delta(
              backgroundColor: FVariantsValueDelta.delta([
                FVariantValueDeltaOperation.all(
                  feedbackColor.withValues(alpha: 0.12),
                ),
              ]),
            ),
      title: Text(
        current.question.options[originalIndex],
        style: feedbackColor == null
            ? null
            : TextStyle(color: feedbackColor, fontWeight: FontWeight.w600),
      ),
      selected: isSelected,
      suffix: !revealed
          ? (isSelected
                ? Icon(FIcons.circleCheck, color: feedbackColor)
                : null)
          : isCorrectOption
          ? Icon(FIcons.circleCheck, color: _correctColor)
          : (isSelected ? Icon(FIcons.circleX, color: _incorrectColor) : null),
      onPress: revealed ? null : () => notifier.selectAnswer(originalIndex),
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
          title: Text(
            'Question ${session.currentIndex + 1} / ${session.questions.length}',
          ),
          prefixes: [
            FHeaderAction.back(
              onPress: () async {
                if (await _confirmExit()) {
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          ],
          suffixes: [
            FHeaderAction(
              icon: const Icon(FIcons.send),
              onPress: () => _confirmSubmitEarly(session),
            ),
          ],
        ),
        // top: false — the header already safe-areas itself against the
        // status bar/notch; this keeps the nav row clear of the gesture bar.
        // minimum guarantees visible breathing room even on devices that
        // report a zero/near-zero bottom inset.
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (session.examRemaining != null ||
                  session.questionRemaining != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (session.examRemaining != null)
                      FBadge(
                        child: Text(
                          'Exam: ${_formatDuration(session.examRemaining!)}',
                        ),
                      ),
                    if (session.questionRemaining != null)
                      FBadge(
                        variant: session.questionRemaining!.inSeconds <= 5
                            ? FBadgeVariant.destructive
                            : FBadgeVariant.secondary,
                        child: Text(
                          'Question: ${_formatDuration(session.questionRemaining!)}',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              // Scrolls independently so the question/options size to their
              // own content instead of being stretched to fill the screen —
              // the nav row below always stays pinned to the bottom. The
              // LayoutBuilder + ConstrainedBox(minHeight) lets short content
              // center vertically in the available space while still
              // scrolling normally if it's taller than the screen.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            current.question.questionText,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          FTileGroup(
                            children: [
                              for (final originalIndex in current.optionOrder)
                                _buildOption(
                                  session,
                                  current,
                                  notifier,
                                  originalIndex,
                                ),
                            ],
                          ),
                          if (session.config.mode == AttemptMode.practice &&
                              current.isAnswered) ...[
                            const SizedBox(height: 8),
                            FAlert(
                              variant: current.isCorrect
                                  ? FAlertVariant.primary
                                  : FAlertVariant.destructive,
                              title: Text(
                                current.isCorrect ? 'Correct' : 'Incorrect',
                              ),
                              subtitle: current.question.explanation != null
                                  ? Text(current.question.explanation!)
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
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
                      child: Text(
                        session.isLast
                            ? 'Submit'
                            : (current.isAnswered ? 'Next' : 'Skip'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../models/attempt.dart';
import '../../models/exam_session.dart';
import '../../models/folder.dart';
import '../../models/question_set.dart';
import '../exam/exam_setup_screen.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({
    super.key,
    required this.folder,
    required this.questionSet,
    required this.session,
    required this.savedAttempt,
    this.queuedForSync = false,
  });

  final Folder folder;
  final QuestionSet questionSet;
  final ExamSessionState session;

  /// Null if persisting the attempt to Supabase didn't succeed immediately —
  /// the review below still reflects this session's answers regardless.
  final Attempt? savedAttempt;

  /// True if [savedAttempt] is null because the attempt was queued locally
  /// (offline) rather than lost outright — see `ExamRunnerScreen._finish`.
  final bool queuedForSync;

  @override
  Widget build(BuildContext context) {
    final duration = session.questions.fold<int>(0, (sum, q) => sum + (q.timeTakenSeconds ?? 0));

    return FScaffold(
      header: FHeader.nested(
        title: const Text('Results'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.pop(context))],
      ),
      child: ListView(
        children: [
          if (savedAttempt == null)
            FAlert(
              variant: queuedForSync ? FAlertVariant.primary : FAlertVariant.destructive,
              title: Text(queuedForSync ? 'Saved locally' : 'Not saved'),
              subtitle: Text(
                queuedForSync
                    ? "You're offline — this attempt will sync automatically once you're back online."
                    : 'This attempt could not be uploaded. Your score below is accurate but won\'t appear in history.',
              ),
            ),
          const SizedBox(height: 12),
          FCard(
            title: Text(questionSet.title),
            subtitle: Text('${session.config.mode.name} · ${session.questions.length} questions'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Score: ${session.totalScore}'),
                Text('Correct: ${session.correctCount}  Wrong: ${session.wrongCount}  Skipped: ${session.skippedCount}'),
                Text('Time taken: ${duration ~/ 60}m ${duration % 60}s'),
              ],
            ),
          ),
          if (session.wrongCount > 0 || session.skippedCount > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (session.wrongCount > 0)
                  Expanded(
                    child: FButton(
                      variant: FButtonVariant.outline,
                      prefix: const Icon(FIcons.rotateCcw),
                      onPress: () => _retry(context, AttemptSourceType.wrongAnswersRetry),
                      child: const Text('Retry wrong'),
                    ),
                  ),
                if (session.wrongCount > 0 && session.skippedCount > 0) const SizedBox(width: 12),
                if (session.skippedCount > 0)
                  Expanded(
                    child: FButton(
                      variant: FButtonVariant.outline,
                      prefix: const Icon(FIcons.rotateCcw),
                      onPress: () => _retry(context, AttemptSourceType.skippedRetry),
                      child: const Text('Retry skipped'),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          for (var i = 0; i < session.questions.length; i++) _buildQuestionCard(i, session.questions[i]),
        ],
      ),
    );
  }

  void _retry(BuildContext context, AttemptSourceType sourceType) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ExamSetupScreen(
          folder: folder,
          questionSet: questionSet,
          initialSourceType: sourceType,
        ),
      ),
    );
  }

  Widget _buildQuestionCard(int index, RunnerQuestion rq) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FCard(
        title: Text('Q${index + 1}. ${rq.question.questionText}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              !rq.isAnswered ? 'Skipped' : 'Your answer: ${rq.question.options[rq.selectedOriginalIndex!]}',
            ),
            if (rq.isAnswered && !rq.isCorrect)
              Text('Correct answer: ${rq.question.options[rq.question.correctAnswer]}'),
            if (rq.question.explanation != null) ...[
              const SizedBox(height: 4),
              Text(rq.question.explanation!),
            ],
          ],
        ),
      ),
    );
  }
}

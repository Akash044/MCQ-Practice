import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../models/attempt.dart';
import '../../models/exam_session.dart';
import '../../models/folder.dart';
import '../../models/question_set.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({
    super.key,
    required this.folder,
    required this.questionSet,
    required this.session,
    required this.savedAttempt,
  });

  final Folder folder;
  final QuestionSet questionSet;
  final ExamSessionState session;

  /// Null if persisting the attempt to Supabase failed — the review below
  /// still reflects this session's answers, they just weren't saved.
  final Attempt? savedAttempt;

  @override
  Widget build(BuildContext context) {
    final duration = session.questions.fold<int>(0, (sum, q) => sum + (q.timeTakenSeconds ?? 0));

    return FScaffold(
      header: FHeader.nested(
        title: const Text('Results'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.popUntil(context, (r) => r.isFirst))],
      ),
      child: ListView(
        children: [
          if (savedAttempt == null)
            FAlert(
              variant: FAlertVariant.destructive,
              title: const Text('Not saved'),
              subtitle: const Text('This attempt could not be uploaded. Your score below is accurate but won\'t appear in history.'),
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
          const SizedBox(height: 16),
          for (var i = 0; i < session.questions.length; i++) _buildQuestionCard(i, session.questions[i]),
        ],
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

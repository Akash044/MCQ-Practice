import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/folder.dart';
import '../../models/question_set.dart';
import '../../providers/exam_providers.dart';
import '../../widgets/error_state.dart';
import '../../widgets/learning_curve_view.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key, required this.folder, required this.questionSet});

  final Folder folder;
  final QuestionSet questionSet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attemptsAsync = ref.watch(attemptHistoryProvider(questionSet.id));
    final answersAsync = ref.watch(answersForSetProvider(questionSet.id));
    final questionsAsync = ref.watch(questionsForSetProvider(questionSet.id));

    return FScaffold(
      header: FHeader.nested(
        title: Text('${questionSet.title} · Progress'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.pop(context))],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: attemptsAsync.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (err, stack) =>
              ErrorState(error: err, label: 'Failed to load attempts'),
          data: (attempts) => answersAsync.when(
            loading: () => const Center(child: FCircularProgress()),
            error: (err, stack) =>
                ErrorState(error: err, label: 'Failed to load answers'),
            data: (answers) => questionsAsync.when(
              loading: () => const Center(child: FCircularProgress()),
              error: (err, stack) =>
                  ErrorState(error: err, label: 'Failed to load questions'),
              data: (questions) => ListView(
                children: [
                  LearningCurveView(
                    folder: folder,
                    attempts: attempts,
                    answers: answers,
                    questions: questions,
                    setById: {questionSet.id: questionSet},
                    onAttemptDeleted: () {
                      ref.invalidate(attemptHistoryProvider(questionSet.id));
                      ref.invalidate(answersForSetProvider(questionSet.id));
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

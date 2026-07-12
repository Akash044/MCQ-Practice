import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/folder.dart';
import '../../providers/exam_providers.dart';
import '../../providers/question_set_providers.dart';
import '../../widgets/error_state.dart';
import '../../widgets/learning_curve_view.dart';

/// Aggregated learning curve across every exam currently moved into a
/// subfolder — its own page (rather than shown inline on the subfolder's
/// exam list) so that list doesn't get crowded with a long chart/stats block
/// above it.
class FolderProgressScreen extends ConsumerWidget {
  const FolderProgressScreen({super.key, required this.folder});

  final Folder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attemptsAsync = ref.watch(folderAttemptHistoryProvider(folder.id));
    final answersAsync = ref.watch(folderAnswersProvider(folder.id));
    final questionsAsync = ref.watch(folderQuestionsProvider(folder.id));
    final setsAsync = ref.watch(questionSetsProvider(folder.id));

    return FScaffold(
      header: FHeader.nested(
        title: Text('${folder.name} · Learning Curve'),
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
              data: (questions) => setsAsync.when(
                loading: () => const Center(child: FCircularProgress()),
                error: (err, stack) =>
                    ErrorState(error: err, label: 'Failed to load exams'),
                data: (sets) => ListView(
                  children: [
                    LearningCurveView(
                      folder: folder,
                      attempts: attempts,
                      answers: answers,
                      questions: questions,
                      setById: {for (final s in sets) s.id: s},
                      showExamLabel: sets.length > 1,
                      onAttemptDeleted: () {
                        ref.invalidate(folderAttemptHistoryProvider(folder.id));
                        ref.invalidate(folderAnswersProvider(folder.id));
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

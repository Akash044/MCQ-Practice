import 'package:flutter/material.dart' show MaterialPageRoute, ReorderableDelayedDragStartListener;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/folder.dart';
import '../../models/question_set.dart';
import '../../providers/exam_providers.dart';
import '../../providers/question_set_providers.dart';
import '../../providers/supabase_providers.dart';
import '../../widgets/error_state.dart';
import '../../widgets/learning_curve_view.dart';
import '../exam/exam_setup_screen.dart';
import '../exam/manage_questions_screen.dart';
import '../import/import_screen.dart';
import 'create_subfolder_screen.dart';

class QuestionSetListScreen extends ConsumerStatefulWidget {
  const QuestionSetListScreen({super.key, required this.folder});

  final Folder folder;

  @override
  ConsumerState<QuestionSetListScreen> createState() =>
      _QuestionSetListScreenState();
}

class _QuestionSetListScreenState
    extends ConsumerState<QuestionSetListScreen> {
  /// Local optimistic copy used while a drag-reorder is in flight, so the
  /// list doesn't snap back to the old order for the round trip to Supabase.
  List<QuestionSet>? _reordering;

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final imported = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ImportScreen(folder: widget.folder),
      ),
    );
    if (imported == true) {
      ref.invalidate(questionSetsProvider(widget.folder.id));
    }
  }

  Future<void> _createSubfolder(BuildContext context, WidgetRef ref) async {
    final currentExams =
        ref.read(questionSetsProvider(widget.folder.id)).valueOrNull ?? [];
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CreateSubfolderScreen(
          parentFolder: widget.folder,
          availableExams: currentExams,
        ),
      ),
    );
    if (created == true) {
      ref.invalidate(childFoldersProvider(widget.folder.id));
      ref.invalidate(questionSetsProvider(widget.folder.id));
    }
  }

  Future<void> _reorder(List<QuestionSet> current, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final updated = List.of(current);
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    setState(() => _reordering = updated);
    try {
      await ref
          .read(supabaseServiceProvider)
          .reorderQuestionSets(updated.map((s) => s.id).toList());
    } finally {
      if (mounted) {
        ref.invalidate(questionSetsProvider(widget.folder.id));
        setState(() => _reordering = null);
      }
    }
  }

  Future<void> _manageQuestions(QuestionSet set) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManageQuestionsScreen(questionSet: set),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final setsAsync = ref.watch(questionSetsProvider(widget.folder.id));
    final childFoldersAsync = ref.watch(childFoldersProvider(widget.folder.id));
    final isSubfolder = widget.folder.parentId != null;

    return FScaffold(
      header: FHeader.nested(
        title: Text(widget.folder.name),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.pop(context))],
        suffixes: [
          FHeaderAction(
            icon: const Icon(FIcons.folderPlus),
            onPress: () => _createSubfolder(context, ref),
          ),
          FHeaderAction(
            icon: const Icon(FIcons.upload),
            onPress: () => _import(context, ref),
          ),
        ],
      ),
      child: setsAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (err, stack) =>
            ErrorState(error: err, label: 'Failed to load question sets'),
        data: (fetched) => childFoldersAsync.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (err, stack) =>
              ErrorState(error: err, label: 'Failed to load subfolders'),
          data: (subfolders) {
            final sets = _reordering ?? fetched;
            if (sets.isEmpty && subfolders.isEmpty) {
              return const Center(
                child: Text(
                  'Nothing here yet. Tap the folder icon to add a subfolder, '
                  'or the upload icon to import an exam.',
                ),
              );
            }
            return CustomScrollView(
              slivers: [
                if (isSubfolder)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: _SubfolderLearningCurve(folder: widget.folder),
                    ),
                  ),
                if (subfolders.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildSubfoldersSection(context, subfolders),
                  ),
                if (sets.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Press and hold an exam, then drag to reorder.',
                        style: context.theme.typography.xs,
                      ),
                    ),
                  ),
                  SliverReorderableList(
                    // See the (touch-platform) default long-press-to-drag
                    // behavior ReorderableListView.builder used to rely on
                    // here — ReorderableDelayedDragStartListener wrapping the
                    // whole row is the same underlying primitive, so taps on
                    // nested controls (the manage-questions icon) still pass
                    // through normally instead of competing with a tiny
                    // nested drag handle.
                    itemCount: sets.length,
                    onReorder: (oldIndex, newIndex) =>
                        _reorder(sets, oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      final set = sets[index];
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(set.id),
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: FTile(
                            prefix: const Icon(FIcons.listChecks),
                            title: Text(
                              set.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: set.subject != null
                                ? Text(set.subject!)
                                : null,
                            suffix: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () => _manageQuestions(set),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 8,
                                    ),
                                    child: Icon(FIcons.listPlus),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(FIcons.gripVertical),
                              ],
                            ),
                            onPress: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ExamSetupScreen(
                                  folder: widget.folder,
                                  questionSet: set,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ] else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'No exams directly in this folder yet. Tap the upload icon to import one.',
                        style: context.theme.typography.sm,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSubfoldersSection(BuildContext context, List<Folder> subfolders) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Subfolders', style: context.theme.typography.sm),
          const SizedBox(height: 8),
          FTileGroup(
            children: [
              for (final sub in subfolders)
                FTile(
                  prefix: const Icon(FIcons.folder),
                  title: Text(sub.name),
                  suffix: const Icon(FIcons.chevronRight),
                  onPress: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => QuestionSetListScreen(folder: sub),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Aggregated learning curve across every exam currently moved into
/// [folder] — only rendered when [folder] is itself a subfolder, per the
/// "show learning curve subfolder-wise when opened" requirement.
class _SubfolderLearningCurve extends ConsumerWidget {
  const _SubfolderLearningCurve({required this.folder});

  final Folder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attemptsAsync = ref.watch(folderAttemptHistoryProvider(folder.id));
    final answersAsync = ref.watch(folderAnswersProvider(folder.id));
    final questionsAsync = ref.watch(folderQuestionsProvider(folder.id));
    final setsAsync = ref.watch(questionSetsProvider(folder.id));

    return attemptsAsync.when(
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
            data: (sets) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Learning curve', style: context.theme.typography.lg),
                const SizedBox(height: 12),
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
    );
  }
}

import 'package:flutter/material.dart' show MaterialPageRoute, ReorderableListView;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/folder.dart';
import '../../models/question_set.dart';
import '../../providers/question_set_providers.dart';
import '../../providers/supabase_providers.dart';
import '../../widgets/error_state.dart';
import '../exam/exam_setup_screen.dart';
import '../exam/manage_questions_screen.dart';
import '../import/import_screen.dart';

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

    return FScaffold(
      header: FHeader.nested(
        title: Text(widget.folder.name),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.pop(context))],
        suffixes: [
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
        data: (fetched) {
          final sets = _reordering ?? fetched;
          if (sets.isEmpty) {
            return const Center(
              child: Text(
                'No question sets in this folder yet. Tap the upload icon to import one.',
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Press and hold an exam, then drag to reorder.',
                  style: context.theme.typography.xs,
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  // Default behavior on touch platforms (long-press anywhere
                  // on the row to start dragging) is what
                  // ReorderableListView is actually built and tested for.
                  // An earlier version of this screen hand-rolled a small
                  // drag-handle icon nested inside FTile's suffix using a
                  // manual ReorderableDragStartListener, which turned out to
                  // be unreliable — FTile's own tap handling competed with
                  // the tiny nested hit target. Letting the framework wrap
                  // the whole item is far more robust.
                  itemCount: sets.length,
                  onReorder: (oldIndex, newIndex) =>
                      _reorder(sets, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final set = sets[index];
                    return Padding(
                      key: ValueKey(set.id),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FTile(
                        prefix: const Icon(FIcons.listChecks),
                        title: Text(set.title),
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
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

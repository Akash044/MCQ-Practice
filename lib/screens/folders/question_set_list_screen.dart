import 'package:flutter/material.dart'
    show MaterialPageRoute, ReorderableDelayedDragStartListener, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/folder.dart';
import '../../models/question_set.dart';
import '../../providers/question_set_providers.dart';
import '../../providers/supabase_providers.dart';
import '../../providers/tts_providers.dart';
import '../../utils/network_error.dart';
import '../../widgets/error_state.dart';
import '../exam/exam_setup_screen.dart';
import '../exam/listen_playback_screen.dart';
import '../exam/manage_questions_screen.dart';
import '../import/import_screen.dart';
import '../progress/folder_progress_screen.dart';
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
  /// Local optimistic copies used while a drag-reorder is in flight, so the
  /// relevant list doesn't snap back to the old order for the round trip to
  /// Supabase.
  List<QuestionSet>? _reordering;
  List<Folder>? _reorderingFolders;

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

  Future<void> _renameFolder(
    BuildContext context,
    WidgetRef ref,
    Folder folder,
  ) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showFDialog<String>(
      context: context,
      builder: (context, style, animation) => FDialog(
        title: const Text('Rename Subfolder'),
        body: FTextField(
          autofocus: true,
          hint: 'e.g. Chapter 1',
          control: FTextFieldControl.managed(controller: controller),
        ),
        actions: [
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FButton(
            onPress: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == folder.name) return;
    try {
      await withConnectivityCheck(
        () => ref.read(supabaseServiceProvider).renameFolder(folder.id, name),
      );
      ref.invalidate(childFoldersProvider(widget.folder.id));
    } catch (e) {
      if (context.mounted) {
        showFToast(
          context: context,
          variant: FToastVariant.destructive,
          title: Text(
            e is NoInternetException
                ? 'No internet connection'
                : 'Could not rename subfolder',
          ),
        );
      }
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

  Future<void> _reorderFolders(
    List<Folder> current,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final updated = List.of(current);
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    setState(() => _reorderingFolders = updated);
    try {
      await ref
          .read(supabaseServiceProvider)
          .reorderFolders(updated.map((f) => f.id).toList());
    } finally {
      if (mounted) {
        ref.invalidate(childFoldersProvider(widget.folder.id));
        setState(() => _reorderingFolders = null);
      }
    }
  }

  Future<void> _chooseVoice() async {
    final tts = ref.read(ttsServiceProvider);
    // Every voice the device offers, not just English ones — question
    // content isn't necessarily English (e.g. Bengali), and filtering to
    // "en*" locales would hide the exact voices that can pronounce it.
    final options = await tts.listVoices();
    if (!mounted) return;
    if (options.isEmpty) {
      showFToast(
        context: context,
        variant: FToastVariant.destructive,
        title: const Text('No voices available on this device'),
      );
      return;
    }

    await showFDialog<void>(
      context: context,
      builder: (context, style, animation) => StatefulBuilder(
        builder: (context, setDialogState) {
          final current = ref.read(ttsVoiceProvider);
          return FDialog(
            title: const Text('Choose a voice'),
            body: SizedBox(
              width: double.maxFinite,
              height: 320,
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final voice = options[index];
                  final isSelected =
                      current?['name'] == voice['name'] &&
                      current?['locale'] == voice['locale'];
                  return FTile(
                    title: Text(voice['name']!),
                    subtitle: Text(voice['locale']!),
                    suffix: isSelected ? const Icon(FIcons.check) : null,
                    onPress: () async {
                      ref.read(ttsVoiceProvider.notifier).setVoice(voice);
                      setDialogState(() {});
                      await tts.setVoice(voice);
                      await tts.speak('This is a preview of this voice.');
                    },
                  );
                },
              ),
            ),
            actions: [
              FButton(
                onPress: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _startListenMode(QuestionSet set) async {
    final controller = TextEditingController(
      text: '${ref.read(ttsAnswerDelaySecondsProvider)}',
    );
    final seconds = await showFDialog<int>(
      context: context,
      builder: (context, style, animation) => FDialog(
        title: const Text('Listen & Answer'),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FTextField(
              autofocus: true,
              label: const Text('Seconds before the answer is read aloud'),
              keyboardType: TextInputType.number,
              control: FTextFieldControl.managed(controller: controller),
            ),
            const SizedBox(height: 12),
            FButton(
              variant: FButtonVariant.outline,
              onPress: _chooseVoice,
              prefix: const Icon(FIcons.mic),
              child: const Text('Choose voice'),
            ),
          ],
        ),
        actions: [
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FButton(
            onPress: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    if (seconds == null || seconds < 0 || !mounted) return;
    ref.read(ttsAnswerDelaySecondsProvider.notifier).setSeconds(seconds);
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ListenPlaybackScreen(
          questionSet: set,
          answerDelaySeconds: seconds,
        ),
      ),
    );
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
          if (isSubfolder)
            FHeaderAction(
              icon: const Icon(FIcons.chartLine),
              onPress: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      FolderProgressScreen(folder: widget.folder),
                ),
              ),
            ),
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
          data: (fetchedSubfolders) {
            final sets = _reordering ?? fetched;
            final subfolders = _reorderingFolders ?? fetchedSubfolders;
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
                if (subfolders.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Subfolders', style: context.theme.typography.sm),
                        const SizedBox(height: 8),
                        Text(
                          'Press and hold a subfolder, then drag to reorder.',
                          style: context.theme.typography.xs,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  SliverReorderableList(
                    itemCount: subfolders.length,
                    onReorder: (oldIndex, newIndex) =>
                        _reorderFolders(subfolders, oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      final sub = subfolders[index];
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(sub.id),
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: FTile(
                            prefix: const Icon(FIcons.folder),
                            title: Text(sub.name),
                            suffix: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () =>
                                      _renameFolder(context, ref, sub),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 8,
                                    ),
                                    child: Icon(FIcons.pencil),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(FIcons.chevronRight),
                              ],
                            ),
                            onPress: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    QuestionSetListScreen(folder: sub),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                ],
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
                                  onTap: () => _startListenMode(set),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 8,
                                    ),
                                    child: Icon(FIcons.play),
                                  ),
                                ),
                                const SizedBox(width: 4),
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
}

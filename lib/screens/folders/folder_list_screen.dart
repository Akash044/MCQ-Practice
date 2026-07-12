import 'package:flutter/material.dart' show MaterialPageRoute, ReorderableListView, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/folder.dart';
import '../../providers/supabase_providers.dart';
import '../../providers/theme_provider.dart';
import '../../utils/network_error.dart';
import '../../widgets/error_state.dart';
import '../custom/custom_exam_builder_screen.dart';
import '../custom/random_mix_exam_screen.dart';
import 'question_set_list_screen.dart';

class FolderListScreen extends ConsumerStatefulWidget {
  const FolderListScreen({super.key});

  @override
  ConsumerState<FolderListScreen> createState() => _FolderListScreenState();
}

class _FolderListScreenState extends ConsumerState<FolderListScreen> {
  /// Local optimistic copy used while a drag-reorder is in flight, so the
  /// list doesn't snap back to the old order for the round trip to Supabase.
  List<Folder>? _reordering;

  Future<void> _createFolder(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showFDialog<String>(
      context: context,
      builder: (context, style, animation) => FDialog(
        title: const Text('New Folder'),
        body: FTextField(
          autofocus: true,
          hint: 'e.g. BCS Model Test',
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await withConnectivityCheck(
        () => ref.read(supabaseServiceProvider).createFolder(name),
      );
      ref.invalidate(foldersProvider);
    } catch (e) {
      if (context.mounted) {
        showFToast(
          context: context,
          variant: FToastVariant.destructive,
          title: Text(
            e is NoInternetException
                ? 'No internet connection'
                : 'Could not create folder',
          ),
        );
      }
    }
  }

  Future<void> _openCustomExamChooser(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final choice = await showFDialog<int>(
      context: context,
      builder: (context, style, animation) => FDialog(
        title: const Text('Create Custom Exam'),
        body: const Text('Build a new exam from questions you already have.'),
        direction: Axis.vertical,
        actions: [
          FButton(
            onPress: () => Navigator.pop(context, 1),
            child: const Text('Pick questions from one exam'),
          ),
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.pop(context, 2),
            child: const Text('Random mix from several exams'),
          ),
          FButton(
            variant: FButtonVariant.ghost,
            onPress: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => choice == 1
            ? const CustomExamBuilderScreen()
            : const RandomMixExamScreen(),
      ),
    );
    if (created == true) ref.invalidate(foldersProvider);
  }

  Future<void> _reorder(List<Folder> current, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final updated = List.of(current);
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    setState(() => _reordering = updated);
    try {
      await ref
          .read(supabaseServiceProvider)
          .reorderFolders(updated.map((f) => f.id).toList());
    } finally {
      if (mounted) {
        ref.invalidate(foldersProvider);
        setState(() => _reordering = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(foldersProvider);
    final themeMode = ref.watch(themeModeProvider);
    final resolvedBrightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final isDark = resolvedBrightness == Brightness.dark;

    return FScaffold(
      header: FHeader(
        title: const Text('MCQ Practice'),
        suffixes: [
          FHeaderAction(
            icon: Icon(isDark ? FIcons.sun : FIcons.moon),
            onPress: () =>
                ref.read(themeModeProvider.notifier).toggle(resolvedBrightness),
          ),
          FHeaderAction(
            icon: const Icon(FIcons.copyPlus),
            onPress: () => _openCustomExamChooser(context, ref),
          ),
          FHeaderAction(
            icon: const Icon(FIcons.folderPlus),
            onPress: () => _createFolder(context, ref),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Folders', style: context.theme.typography.lg),
          const SizedBox(height: 12),
          Expanded(
            child: foldersAsync.when(
              loading: () => const Center(child: FCircularProgress()),
              error: (err, stack) =>
                  ErrorState(error: err, label: 'Failed to load folders'),
              data: (fetched) {
                final folders = _reordering ?? fetched;
                if (folders.isEmpty) {
                  return const Center(
                    child: Text('No folders yet. Tap + to create one.'),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Press and hold a folder, then drag to reorder.',
                      style: context.theme.typography.xs,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      // Default behavior on touch platforms (long-press
                      // anywhere on the row to start dragging) is what
                      // ReorderableListView.builder is built and tested for
                      // (see the exam-list screen's identical choice) — no
                      // extra manual drag listener needed here.
                      child: ReorderableListView.builder(
                        itemCount: folders.length,
                        onReorder: (oldIndex, newIndex) =>
                            _reorder(folders, oldIndex, newIndex),
                        itemBuilder: (context, index) {
                          final folder = folders[index];
                          return Padding(
                            key: ValueKey(folder.id),
                            padding: const EdgeInsets.only(bottom: 8),
                            child: FTile(
                              prefix: const Icon(FIcons.folder),
                              title: Text(folder.name),
                              suffix: const Icon(FIcons.chevronRight),
                              onPress: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      QuestionSetListScreen(folder: folder),
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
          ),
        ],
      ),
    );
  }
}

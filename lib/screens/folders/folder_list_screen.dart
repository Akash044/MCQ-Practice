import 'package:flutter/material.dart' show MaterialPageRoute, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/folder.dart';
import '../../providers/supabase_providers.dart';
import '../../providers/theme_provider.dart';
import '../../utils/network_error.dart';
import '../../widgets/error_state.dart';
import 'question_set_list_screen.dart';

class FolderListScreen extends ConsumerWidget {
  const FolderListScreen({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              data: (folders) {
                if (folders.isEmpty) {
                  return const Center(
                    child: Text('No folders yet. Tap + to create one.'),
                  );
                }
                // Wrapped in a Column (loose, top-aligned constraints) rather
                // than returned directly, so the tile group's box sizes to
                // its content instead of stretching to fill this Expanded.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FTileGroup(
                      children: [
                        for (final Folder folder in folders)
                          FTile(
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
                      ],
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

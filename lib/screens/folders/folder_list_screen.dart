import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/folder.dart';
import '../../providers/supabase_providers.dart';
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
    await ref.read(supabaseServiceProvider).createFolder(name);
    ref.invalidate(foldersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(foldersProvider);

    return FScaffold(
      header: FHeader(
        title: const Text('Folders'),
        suffixes: [
          FHeaderAction(
            icon: const Icon(FIcons.folderPlus),
            onPress: () => _createFolder(context, ref),
          ),
        ],
      ),
      child: foldersAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (err, stack) => Center(child: Text('Failed to load folders: $err')),
        data: (folders) {
          if (folders.isEmpty) {
            return const Center(
              child: Text('No folders yet. Tap + to create one.'),
            );
          }
          return FTileGroup(
            children: [
              for (final Folder folder in folders)
                FTile(
                  prefix: const Icon(FIcons.folder),
                  title: Text(folder.name),
                  suffix: const Icon(FIcons.chevronRight),
                  onPress: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => QuestionSetListScreen(folder: folder),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

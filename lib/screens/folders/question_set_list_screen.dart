import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/folder.dart';
import '../../providers/question_set_providers.dart';
import '../exam/exam_setup_screen.dart';
import '../import/import_screen.dart';

class QuestionSetListScreen extends ConsumerWidget {
  const QuestionSetListScreen({super.key, required this.folder});

  final Folder folder;

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final imported = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ImportScreen(folder: folder),
      ),
    );
    if (imported == true) {
      ref.invalidate(questionSetsProvider(folder.id));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setsAsync = ref.watch(questionSetsProvider(folder.id));

    return FScaffold(
      header: FHeader.nested(
        title: Text(folder.name),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.pop(context)),
        ],
        suffixes: [
          FHeaderAction(
            icon: const Icon(FIcons.upload),
            onPress: () => _import(context, ref),
          ),
        ],
      ),
      child: setsAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (err, stack) => Center(child: Text('Failed to load sets: $err')),
        data: (sets) {
          if (sets.isEmpty) {
            return const Center(
              child: Text('No question sets in this folder yet. Tap the upload icon to import one.'),
            );
          }
          return FTileGroup(
            children: [
              for (final set in sets)
                FTile(
                  prefix: const Icon(FIcons.listChecks),
                  title: Text(set.title),
                  subtitle: set.subject != null ? Text(set.subject!) : null,
                  suffix: const Icon(FIcons.chevronRight),
                  onPress: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ExamSetupScreen(folder: folder, questionSet: set),
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

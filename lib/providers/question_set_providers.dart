import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/folder.dart';
import '../models/question_set.dart';
import '../utils/network_error.dart';
import 'supabase_providers.dart';

final questionSetsProvider = FutureProvider.family<List<QuestionSet>, String>((
  ref,
  folderId,
) async {
  return withConnectivityCheck(
    () => ref.watch(supabaseServiceProvider).fetchQuestionSets(folderId),
  );
});

/// Every exam across every folder, each paired with its folder — used by the
/// random-mix exam builder to offer a single flat, folder-labeled list to
/// pick from instead of drilling into one folder at a time.
final allQuestionSetsWithFolderProvider =
    FutureProvider<List<(Folder, QuestionSet)>>((ref) async {
      return withConnectivityCheck(() async {
        final service = ref.watch(supabaseServiceProvider);
        final folders = await service.fetchFolders();
        final result = <(Folder, QuestionSet)>[];
        for (final folder in folders) {
          final sets = await service.fetchQuestionSets(folder.id);
          for (final set in sets) {
            result.add((folder, set));
          }
        }
        return result;
      });
    });

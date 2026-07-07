import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/question_set.dart';
import 'supabase_providers.dart';

final questionSetsProvider =
    FutureProvider.family<List<QuestionSet>, String>((ref, folderId) async {
  return ref.watch(supabaseServiceProvider).fetchQuestionSets(folderId);
});

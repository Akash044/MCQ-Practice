import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attempt.dart';
import '../models/attempt_answer.dart';
import '../models/question.dart';
import '../services/local_db.dart';
import '../utils/network_error.dart';
import 'question_set_providers.dart';
import 'supabase_providers.dart';

/// Fetches a set's questions from Supabase and refreshes the local cache on
/// success; if the network call fails because the device is offline, falls
/// back to whatever was last cached so a previously-loaded set can still be
/// retaken (docs/PRD.md section 8). Any other error (a real API/DB error) is
/// rethrown instead of being masked by a stale cache hit — otherwise, e.g., a
/// question add/delete whose subsequent refetch hits a transient error would
/// silently keep showing the pre-mutation list with no indication anything
/// went wrong.
final questionsForSetProvider = FutureProvider.family<List<Question>, String>((
  ref,
  setId,
) async {
  final service = ref.watch(supabaseServiceProvider);
  try {
    final questions = await service.fetchQuestions(setId);
    await LocalDb.cacheQuestions(setId, questions);
    return questions;
  } on Object catch (e) {
    try {
      await withConnectivityCheck(() => Future<void>.error(e));
    } on NoInternetException {
      final cached = await LocalDb.getCachedQuestions(setId);
      if (cached.isNotEmpty) return cached;
    }
    rethrow;
  }
});

final answersForSetProvider =
    FutureProvider.family<List<AttemptAnswer>, String>((ref, setId) async {
      return withConnectivityCheck(
        () => ref.watch(supabaseServiceProvider).fetchAllAnswersForSet(setId),
      );
    });

final attemptHistoryProvider = FutureProvider.family<List<Attempt>, String>((
  ref,
  setId,
) async {
  return withConnectivityCheck(
    () => ref.watch(supabaseServiceProvider).fetchAttemptHistory(setId),
  );
});

/// Aggregated versions of the three providers above, spanning every exam
/// that's been moved into a subfolder — feed that subfolder's own learning
/// curve (docs the "chapter" grouping's per-subfolder progress view).

final folderAttemptHistoryProvider =
    FutureProvider.family<List<Attempt>, String>((ref, folderId) async {
      final sets = await ref.watch(questionSetsProvider(folderId).future);
      return withConnectivityCheck(
        () => ref
            .watch(supabaseServiceProvider)
            .fetchAttemptHistoryForSets(sets.map((s) => s.id).toList()),
      );
    });

final folderAnswersProvider = FutureProvider.family<List<AttemptAnswer>, String>((
  ref,
  folderId,
) async {
  final sets = await ref.watch(questionSetsProvider(folderId).future);
  return withConnectivityCheck(
    () => ref
        .watch(supabaseServiceProvider)
        .fetchAllAnswersForSets(sets.map((s) => s.id).toList()),
  );
});

final folderQuestionsProvider = FutureProvider.family<List<Question>, String>((
  ref,
  folderId,
) async {
  final sets = await ref.watch(questionSetsProvider(folderId).future);
  return withConnectivityCheck(
    () => ref
        .watch(supabaseServiceProvider)
        .fetchQuestionsForSets(sets.map((s) => s.id).toList()),
  );
});

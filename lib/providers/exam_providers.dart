import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attempt.dart';
import '../models/attempt_answer.dart';
import '../models/question.dart';
import '../services/local_db.dart';
import '../utils/network_error.dart';
import 'supabase_providers.dart';

/// Fetches a set's questions from Supabase and refreshes the local cache on
/// success; if the network call fails (offline), falls back to whatever was
/// last cached so a previously-loaded set can still be retaken (docs/PRD.md
/// section 8: exams should be takeable offline once questions are loaded).
final questionsForSetProvider = FutureProvider.family<List<Question>, String>((
  ref,
  setId,
) async {
  final service = ref.watch(supabaseServiceProvider);
  try {
    final questions = await service.fetchQuestions(setId);
    await LocalDb.cacheQuestions(setId, questions);
    return questions;
  } catch (e) {
    final cached = await LocalDb.getCachedQuestions(setId);
    if (cached.isNotEmpty) return cached;
    return withConnectivityCheck(() => Future<List<Question>>.error(e));
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

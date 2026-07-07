import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attempt_answer.dart';
import '../models/question.dart';
import 'supabase_providers.dart';

final questionsForSetProvider = FutureProvider.family<List<Question>, String>((ref, setId) async {
  return ref.watch(supabaseServiceProvider).fetchQuestions(setId);
});

final answersForSetProvider = FutureProvider.family<List<AttemptAnswer>, String>((ref, setId) async {
  return ref.watch(supabaseServiceProvider).fetchAllAnswersForSet(setId);
});

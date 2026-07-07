import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/attempt.dart';
import '../models/attempt_answer.dart';
import '../models/folder.dart';
import '../models/question.dart';
import '../models/question_set.dart';

/// Thin wrapper around the Supabase client for the tables defined in
/// supabase/schema.sql. Kept free of Riverpod so it's easy to unit test.
class SupabaseService {
  SupabaseService(this._client);

  final SupabaseClient _client;

  // --- Folders ---------------------------------------------------------

  Future<List<Folder>> fetchFolders() async {
    final rows = await _client.from('folders').select().order('name');
    return rows.map((row) => Folder.fromMap(row)).toList();
  }

  Future<Folder> createFolder(String name, {String? parentId}) async {
    final row = await _client
        .from('folders')
        .insert({'name': name, 'parent_id': ?parentId})
        .select()
        .single();
    return Folder.fromMap(row);
  }

  // --- Question sets -----------------------------------------------------

  Future<List<QuestionSet>> fetchQuestionSets(String folderId) async {
    final rows = await _client
        .from('question_sets')
        .select()
        .eq('folder_id', folderId)
        .order('created_at', ascending: false);
    return rows.map((row) => QuestionSet.fromMap(row)).toList();
  }

  /// Inserts the question set and its questions in one call. Not wrapped in
  /// a DB transaction (supabase-js/dart has no client-side transaction API);
  /// if the questions insert fails, the caller should delete the orphaned
  /// question_set row (cascade delete handles cleanup either way).
  Future<QuestionSet> importQuestionSet({
    required String folderId,
    required String title,
    String? subject,
    num defaultMarksPerCorrect = 1,
    num defaultNegativeMarksPerWrong = 0,
    required List<Question> questions,
  }) async {
    final setRow = await _client
        .from('question_sets')
        .insert({
          'folder_id': folderId,
          'title': title,
          'subject': ?subject,
          'default_marks_per_correct': defaultMarksPerCorrect,
          'default_negative_marks_per_wrong': defaultNegativeMarksPerWrong,
        })
        .select()
        .single();
    final questionSet = QuestionSet.fromMap(setRow);

    try {
      await _client.from('questions').insert(
            questions
                .map((q) => Question(
                      id: q.id,
                      questionSetId: questionSet.id,
                      sourceId: q.sourceId,
                      questionText: q.questionText,
                      options: q.options,
                      correctAnswer: q.correctAnswer,
                      explanation: q.explanation,
                      topic: q.topic,
                      difficulty: q.difficulty,
                      createdAt: q.createdAt,
                    ).toInsertMap())
                .toList(),
          );
    } catch (_) {
      await _client.from('question_sets').delete().eq('id', questionSet.id);
      rethrow;
    }

    return questionSet;
  }

  Future<List<Question>> fetchQuestions(String questionSetId) async {
    final rows = await _client
        .from('questions')
        .select()
        .eq('question_set_id', questionSetId);
    return rows.map((row) => Question.fromMap(row)).toList();
  }

  // --- Attempts ------------------------------------------------------------

  Future<Attempt> createAttempt(Attempt attempt) async {
    final row = await _client
        .from('attempts')
        .insert(attempt.toInsertMap())
        .select()
        .single();
    return Attempt.fromMap(row);
  }

  Future<void> saveAttemptAnswers(List<AttemptAnswer> answers) async {
    await _client
        .from('attempt_answers')
        .insert(answers.map((a) => a.toInsertMap()).toList());
  }

  /// Raw-map variants used by [LocalDb]'s pending-sync queue: a queued
  /// attempt is stored as plain insert payloads (not [Attempt]/[AttemptAnswer]
  /// instances) since it's serialized to disk while offline and replayed
  /// later, possibly across app restarts.
  Future<Map<String, dynamic>> insertAttemptRaw(Map<String, dynamic> insertMap) async {
    return _client.from('attempts').insert(insertMap).select().single();
  }

  Future<void> insertAttemptAnswersRaw(List<Map<String, dynamic>> insertMaps) async {
    await _client.from('attempt_answers').insert(insertMaps);
  }

  Future<List<Attempt>> fetchAttemptHistory(String questionSetId) async {
    final rows = await _client
        .from('attempts')
        .select()
        .eq('question_set_id', questionSetId)
        .order('started_at', ascending: false);
    return rows.map((row) => Attempt.fromMap(row)).toList();
  }

  // --- Wrong-answer / skipped pools (docs/PRD.md section 6 derived views) --

  /// Most recent attempt_answer per question, across attempts of this set,
  /// used to derive the current wrong-answer and skipped pools client-side.
  Future<List<AttemptAnswer>> fetchAllAnswersForSet(String questionSetId) async {
    final rows = await _client
        .from('attempt_answers')
        .select('*, attempts!inner(question_set_id)')
        .eq('attempts.question_set_id', questionSetId)
        .order('answered_at');
    return rows.map((row) => AttemptAnswer.fromMap(row)).toList();
  }
}

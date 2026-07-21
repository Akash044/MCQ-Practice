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

  /// Top-level folders only (subjects), for the home screen — subfolders
  /// (chapters) are fetched separately via [fetchChildFolders] so they only
  /// ever show up nested inside their parent.
  Future<List<Folder>> fetchRootFolders() async {
    final rows = await _client
        .from('folders')
        .select()
        .isFilter('parent_id', null)
        .order('position', ascending: true)
        .order('name');
    return rows.map((row) => Folder.fromMap(row)).toList();
  }

  /// Subfolders (chapters) directly under [parentId].
  Future<List<Folder>> fetchChildFolders(String parentId) async {
    final rows = await _client
        .from('folders')
        .select()
        .eq('parent_id', parentId)
        .order('position', ascending: true)
        .order('name');
    return rows.map((row) => Folder.fromMap(row)).toList();
  }

  Future<Folder> createFolder(String name, {String? parentId}) async {
    final position = await _nextPositionAmongSiblings(parentId);
    final row = await _client
        .from('folders')
        .insert({'name': name, 'parent_id': ?parentId, 'position': position})
        .select()
        .single();
    return Folder.fromMap(row);
  }

  /// New folders are appended after whatever currently has the highest
  /// `position` among siblings (same `parent_id`, including the root group
  /// where it's null), so drag-reordering never has to touch existing rows
  /// just because a new folder/subfolder was created.
  Future<int> _nextPositionAmongSiblings(String? parentId) async {
    var query = _client.from('folders').select('position');
    query = parentId == null
        ? query.isFilter('parent_id', null)
        : query.eq('parent_id', parentId);
    final rows = await query.order('position', ascending: false).limit(1);
    if (rows.isEmpty) return 0;
    return ((rows.first['position'] as int?) ?? 0) + 1;
  }

  /// Persists a drag-reorder of a set of sibling folders (either the root
  /// folders on the home screen, or the subfolders within one parent).
  /// [orderedFolderIds] must be the full, newly-ordered list of ids for that
  /// sibling group — each gets its list index written back as its `position`.
  Future<void> reorderFolders(List<String> orderedFolderIds) async {
    for (var i = 0; i < orderedFolderIds.length; i++) {
      await _client
          .from('folders')
          .update({'position': i})
          .eq('id', orderedFolderIds[i]);
    }
  }

  /// Renames an existing folder or subfolder in place; parent and position
  /// are left untouched.
  Future<Folder> renameFolder(String id, String name) async {
    final row = await _client
        .from('folders')
        .update({'name': name})
        .eq('id', id)
        .select()
        .single();
    return Folder.fromMap(row);
  }

  /// Returns the existing folder named [name] (case-insensitive), or creates
  /// it if none exists yet — used to land custom exams in a "Custom" folder
  /// without erroring if it's already there from a previous custom exam.
  Future<Folder> findOrCreateFolder(String name) async {
    final folders = await fetchFolders();
    for (final folder in folders) {
      if (folder.name.toLowerCase() == name.toLowerCase()) return folder;
    }
    return createFolder(name);
  }

  // --- Question sets -----------------------------------------------------

  Future<List<QuestionSet>> fetchQuestionSets(String folderId) async {
    final rows = await _client
        .from('question_sets')
        .select()
        .eq('folder_id', folderId)
        .order('position', ascending: true)
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
    final position = await _nextPositionInFolder(folderId);
    final setRow = await _client
        .from('question_sets')
        .insert({
          'folder_id': folderId,
          'title': title,
          'subject': ?subject,
          'default_marks_per_correct': defaultMarksPerCorrect,
          'default_negative_marks_per_wrong': defaultNegativeMarksPerWrong,
          'position': position,
        })
        .select()
        .single();
    final questionSet = QuestionSet.fromMap(setRow);

    try {
      await _client
          .from('questions')
          .insert(
            questions
                .map(
                  (q) => Question(
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
                  ).toInsertMap(),
                )
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

  /// Combined question list across several exams — feeds the per-topic and
  /// weak-spot breakdowns of a subfolder's aggregated learning curve.
  Future<List<Question>> fetchQuestionsForSets(List<String> setIds) async {
    if (setIds.isEmpty) return [];
    final rows = await _client
        .from('questions')
        .select()
        .inFilter('question_set_id', setIds);
    return rows.map((row) => Question.fromMap(row)).toList();
  }

  Future<List<Question>> addQuestions(List<Question> questions) async {
    final rows = await _client
        .from('questions')
        .insert(questions.map((q) => q.toInsertMap()).toList())
        .select();
    return rows.map((row) => Question.fromMap(row)).toList();
  }

  Future<void> deleteQuestion(String questionId) async {
    await _client.from('questions').delete().eq('id', questionId);
  }

  Future<Question> updateQuestion(Question question) async {
    final row = await _client
        .from('questions')
        .update(question.toInsertMap())
        .eq('id', question.id)
        .select()
        .single();
    return Question.fromMap(row);
  }

  // --- Reordering (question_sets.position) --------------------------------

  /// New sets are appended after whatever currently has the highest
  /// `position` in the folder, so drag-reordering never has to touch
  /// existing rows just because a new exam was imported.
  Future<int> _nextPositionInFolder(String folderId) async {
    final rows = await _client
        .from('question_sets')
        .select('position')
        .eq('folder_id', folderId)
        .order('position', ascending: false)
        .limit(1);
    if (rows.isEmpty) return 0;
    return ((rows.first['position'] as int?) ?? 0) + 1;
  }

  /// Persists a drag-reorder of a folder's exams. [orderedSetIds] must be the
  /// full, newly-ordered list of question_set ids for that folder — each
  /// gets its list index written back as its `position`.
  Future<void> reorderQuestionSets(List<String> orderedSetIds) async {
    for (var i = 0; i < orderedSetIds.length; i++) {
      await _client
          .from('question_sets')
          .update({'position': i})
          .eq('id', orderedSetIds[i]);
    }
  }

  /// Moves the given exams into [targetFolderId] — used when picking existing
  /// exams to include in a newly-created subfolder (chapter). Each exam still
  /// belongs to exactly one folder, so this reassigns `folder_id` rather than
  /// creating a second link; the exams disappear from their old folder's list
  /// and only show up under the subfolder from then on. Repositioned to
  /// append after whatever's already in the target, same as a fresh import.
  Future<void> moveQuestionSetsToFolder(
    List<String> setIds,
    String targetFolderId,
  ) async {
    var position = await _nextPositionInFolder(targetFolderId);
    for (final setId in setIds) {
      await _client
          .from('question_sets')
          .update({'folder_id': targetFolderId, 'position': position})
          .eq('id', setId);
      position++;
    }
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
  Future<Map<String, dynamic>> insertAttemptRaw(
    Map<String, dynamic> insertMap,
  ) async {
    return _client.from('attempts').insert(insertMap).select().single();
  }

  Future<void> insertAttemptAnswersRaw(
    List<Map<String, dynamic>> insertMaps,
  ) async {
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

  /// Combined attempt history across several exams — used for a subfolder's
  /// aggregated learning curve, which spans every exam moved into it.
  Future<List<Attempt>> fetchAttemptHistoryForSets(List<String> setIds) async {
    if (setIds.isEmpty) return [];
    final rows = await _client
        .from('attempts')
        .select()
        .inFilter('question_set_id', setIds)
        .order('started_at', ascending: false);
    return rows.map((row) => Attempt.fromMap(row)).toList();
  }

  /// `attempt_answers` rows cascade-delete via their `attempt_id` foreign key
  /// (see supabase/schema.sql), so deleting the attempt is enough.
  Future<void> deleteAttempt(String attemptId) async {
    await _client.from('attempts').delete().eq('id', attemptId);
  }

  // --- Wrong-answer / skipped pools (docs/PRD.md section 6 derived views) --

  /// Most recent attempt_answer per question, across attempts of this set,
  /// used to derive the current wrong-answer and skipped pools client-side.
  Future<List<AttemptAnswer>> fetchAllAnswersForSet(
    String questionSetId,
  ) async {
    final rows = await _client
        .from('attempt_answers')
        .select('*, attempts!inner(question_set_id)')
        .eq('attempts.question_set_id', questionSetId)
        .order('answered_at');
    return rows.map((row) => AttemptAnswer.fromMap(row)).toList();
  }

  /// Combined answer history across several exams — feeds a subfolder's
  /// aggregated learning curve the same derived views a single exam gets.
  Future<List<AttemptAnswer>> fetchAllAnswersForSets(
    List<String> setIds,
  ) async {
    if (setIds.isEmpty) return [];
    final rows = await _client
        .from('attempt_answers')
        .select('*, attempts!inner(question_set_id)')
        .inFilter('attempts.question_set_id', setIds)
        .order('answered_at');
    return rows.map((row) => AttemptAnswer.fromMap(row)).toList();
  }
}

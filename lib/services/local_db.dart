import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/question.dart';

/// Local/offline cache (docs/PRD.md section 1.1 & 8): a copy of each set's
/// questions for offline exam-taking, and a queue of completed attempts that
/// failed to reach Supabase (e.g. no connectivity) so they can be retried
/// later instead of losing the attempt entirely.
class LocalDb {
  LocalDb._();

  static Database? _db;

  static Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;

    final dir = await getDatabasesPath();
    final path = p.join(dir, 'mcq_test.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          create table cached_questions (
            question_set_id text not null,
            id text not null,
            data text not null,
            primary key (question_set_id, id)
          )
        ''');
        await db.execute('''
          create table pending_attempts (
            local_id integer primary key autoincrement,
            attempt_json text not null,
            answers_json text not null,
            created_at text not null
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  static Map<String, dynamic> _questionToCacheMap(Question q) => {
        'id': q.id,
        'created_at': q.createdAt.toIso8601String(),
        ...q.toInsertMap(),
      };

  static Future<void> cacheQuestions(String questionSetId, List<Question> questions) async {
    final db = await _open();
    final batch = db.batch();
    batch.delete('cached_questions', where: 'question_set_id = ?', whereArgs: [questionSetId]);
    for (final q in questions) {
      batch.insert('cached_questions', {
        'question_set_id': questionSetId,
        'id': q.id,
        'data': jsonEncode(_questionToCacheMap(q)),
      });
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Question>> getCachedQuestions(String questionSetId) async {
    final db = await _open();
    final rows = await db.query(
      'cached_questions',
      where: 'question_set_id = ?',
      whereArgs: [questionSetId],
    );
    return rows
        .map((row) => Question.fromMap(jsonDecode(row['data'] as String) as Map<String, dynamic>))
        .toList();
  }

  /// Queues a completed attempt (as raw Supabase insert payloads) for later
  /// sync. [answerMapsWithoutAttemptId] omit `attempt_id` since it isn't
  /// known until the attempt itself is inserted — [SyncService] fills it in
  /// at flush time.
  static Future<void> enqueuePendingAttempt(
    Map<String, dynamic> attemptInsertMap,
    List<Map<String, dynamic>> answerMapsWithoutAttemptId,
  ) async {
    final db = await _open();
    await db.insert('pending_attempts', {
      'attempt_json': jsonEncode(attemptInsertMap),
      'answers_json': jsonEncode(answerMapsWithoutAttemptId),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getPendingAttempts() async {
    final db = await _open();
    return db.query('pending_attempts', orderBy: 'created_at');
  }

  static Future<void> removePendingAttempt(int localId) async {
    final db = await _open();
    await db.delete('pending_attempts', where: 'local_id = ?', whereArgs: [localId]);
  }
}

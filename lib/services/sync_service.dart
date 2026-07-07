import 'dart:convert';

import 'local_db.dart';
import 'supabase_service.dart';

/// Retries attempts queued by [LocalDb] because they couldn't reach
/// Supabase when the exam was submitted (docs/PRD.md section 1.1: "a simple
/// pending sync queue table locally is enough"). Called once at app start
/// and again whenever connectivity is restored (see `lib/main.dart`).
class SyncService {
  SyncService(this._service);

  final SupabaseService _service;

  Future<void> flushPending() async {
    final pending = await LocalDb.getPendingAttempts();
    for (final row in pending) {
      final attemptMap =
          jsonDecode(row['attempt_json'] as String) as Map<String, dynamic>;
      final answerMaps = (jsonDecode(row['answers_json'] as String) as List)
          .cast<Map<String, dynamic>>();
      try {
        final saved = await _service.insertAttemptRaw(attemptMap);
        final attemptId = saved['id'] as String;
        await _service.insertAttemptAnswersRaw([
          for (final a in answerMaps) {...a, 'attempt_id': attemptId},
        ]);
        await LocalDb.removePendingAttempt(row['local_id'] as int);
      } catch (_) {
        // Still offline (or a real server error) — stop for now and let the
        // next trigger (app start / connectivity restored) retry the rest.
        return;
      }
    }
  }
}

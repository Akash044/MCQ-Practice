enum AttemptSourceType { fullSet, wrongAnswersRetry, skippedRetry, custom }

enum AttemptMode { practice, test }

extension AttemptSourceTypeX on AttemptSourceType {
  String get value => switch (this) {
        AttemptSourceType.fullSet => 'full_set',
        AttemptSourceType.wrongAnswersRetry => 'wrong_answers_retry',
        AttemptSourceType.skippedRetry => 'skipped_retry',
        AttemptSourceType.custom => 'custom',
      };

  static AttemptSourceType fromValue(String value) => switch (value) {
        'full_set' => AttemptSourceType.fullSet,
        'wrong_answers_retry' => AttemptSourceType.wrongAnswersRetry,
        'skipped_retry' => AttemptSourceType.skippedRetry,
        'custom' => AttemptSourceType.custom,
        _ => throw ArgumentError('Unknown source_type: $value'),
      };

  /// Attempts whose source is excluded from the main accuracy/progress-trend
  /// analytics per docs/PRD.md section 9 (retry drilling shouldn't inflate
  /// "improvement" stats, but still counts toward mastery streaks).
  bool get countsTowardTrendCharts =>
      this == AttemptSourceType.fullSet || this == AttemptSourceType.custom;
}

extension AttemptModeX on AttemptMode {
  String get value => switch (this) {
        AttemptMode.practice => 'practice',
        AttemptMode.test => 'test',
      };

  static AttemptMode fromValue(String value) => switch (value) {
        'practice' => AttemptMode.practice,
        'test' => AttemptMode.test,
        _ => throw ArgumentError('Unknown mode: $value'),
      };
}

class Attempt {
  final String id;
  final String questionSetId;
  final AttemptSourceType sourceType;
  final AttemptMode mode;
  final num marksPerCorrect;
  final num negativeMarksPerWrong;
  final int? examTimerMinutes;
  final int? perQuestionTimerSeconds;
  final int totalQuestions;
  final int correctCount;
  final int wrongCount;
  final int skippedCount;
  final num? totalScore;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int? durationSeconds;

  const Attempt({
    required this.id,
    required this.questionSetId,
    required this.sourceType,
    required this.mode,
    this.marksPerCorrect = 1,
    this.negativeMarksPerWrong = 0,
    this.examTimerMinutes,
    this.perQuestionTimerSeconds,
    required this.totalQuestions,
    this.correctCount = 0,
    this.wrongCount = 0,
    this.skippedCount = 0,
    this.totalScore,
    required this.startedAt,
    this.completedAt,
    this.durationSeconds,
  });

  factory Attempt.fromMap(Map<String, dynamic> map) {
    return Attempt(
      id: map['id'] as String,
      questionSetId: map['question_set_id'] as String,
      sourceType: AttemptSourceTypeX.fromValue(map['source_type'] as String),
      mode: AttemptModeX.fromValue(map['mode'] as String),
      marksPerCorrect: (map['marks_per_correct'] as num?) ?? 1,
      negativeMarksPerWrong: (map['negative_marks_per_wrong'] as num?) ?? 0,
      examTimerMinutes: map['exam_timer_minutes'] as int?,
      perQuestionTimerSeconds: map['per_question_timer_seconds'] as int?,
      totalQuestions: map['total_questions'] as int,
      correctCount: (map['correct_count'] as int?) ?? 0,
      wrongCount: (map['wrong_count'] as int?) ?? 0,
      skippedCount: (map['skipped_count'] as int?) ?? 0,
      totalScore: map['total_score'] as num?,
      startedAt: DateTime.parse(map['started_at'] as String),
      completedAt: map['completed_at'] != null
          ? DateTime.parse(map['completed_at'] as String)
          : null,
      durationSeconds: map['duration_seconds'] as int?,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'question_set_id': questionSetId,
      'source_type': sourceType.value,
      'mode': mode.value,
      'marks_per_correct': marksPerCorrect,
      'negative_marks_per_wrong': negativeMarksPerWrong,
      if (examTimerMinutes != null) 'exam_timer_minutes': examTimerMinutes,
      if (perQuestionTimerSeconds != null)
        'per_question_timer_seconds': perQuestionTimerSeconds,
      'total_questions': totalQuestions,
      'correct_count': correctCount,
      'wrong_count': wrongCount,
      'skipped_count': skippedCount,
      if (totalScore != null) 'total_score': totalScore,
      'started_at': startedAt.toIso8601String(),
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
    };
  }
}

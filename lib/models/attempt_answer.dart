enum AnswerStatus { correct, incorrect, skipped }

extension AnswerStatusX on AnswerStatus {
  String get value => switch (this) {
        AnswerStatus.correct => 'correct',
        AnswerStatus.incorrect => 'incorrect',
        AnswerStatus.skipped => 'skipped',
      };

  static AnswerStatus fromValue(String value) => switch (value) {
        'correct' => AnswerStatus.correct,
        'incorrect' => AnswerStatus.incorrect,
        'skipped' => AnswerStatus.skipped,
        _ => throw ArgumentError('Unknown status: $value'),
      };
}

class AttemptAnswer {
  final String id;
  final String attemptId;
  final String questionId;
  final int? selectedAnswer;
  final AnswerStatus status;
  final int? timeTakenSeconds;
  final DateTime answeredAt;

  const AttemptAnswer({
    required this.id,
    required this.attemptId,
    required this.questionId,
    this.selectedAnswer,
    required this.status,
    this.timeTakenSeconds,
    required this.answeredAt,
  });

  factory AttemptAnswer.fromMap(Map<String, dynamic> map) {
    return AttemptAnswer(
      id: map['id'] as String,
      attemptId: map['attempt_id'] as String,
      questionId: map['question_id'] as String,
      selectedAnswer: map['selected_answer'] as int?,
      status: AnswerStatusX.fromValue(map['status'] as String),
      timeTakenSeconds: map['time_taken_seconds'] as int?,
      answeredAt: DateTime.parse(map['answered_at'] as String),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'attempt_id': attemptId,
      'question_id': questionId,
      if (selectedAnswer != null) 'selected_answer': selectedAnswer,
      'status': status.value,
      if (timeTakenSeconds != null) 'time_taken_seconds': timeTakenSeconds,
    };
  }
}

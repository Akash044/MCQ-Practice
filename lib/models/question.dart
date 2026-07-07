class Question {
  final String id;
  final String questionSetId;
  final String? sourceId;
  final String questionText;
  final List<String> options;
  final int correctAnswer;
  final String? explanation;
  final String? topic;
  final String? difficulty;
  final DateTime createdAt;

  const Question({
    required this.id,
    required this.questionSetId,
    this.sourceId,
    required this.questionText,
    required this.options,
    required this.correctAnswer,
    this.explanation,
    this.topic,
    this.difficulty,
    required this.createdAt,
  });

  factory Question.fromMap(Map<String, dynamic> map) {
    return Question(
      id: map['id'] as String,
      questionSetId: map['question_set_id'] as String,
      sourceId: map['source_id'] as String?,
      questionText: map['question_text'] as String,
      options: List<String>.from(map['options'] as List),
      correctAnswer: map['correct_answer'] as int,
      explanation: map['explanation'] as String?,
      topic: map['topic'] as String?,
      difficulty: map['difficulty'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Parses a single question object from the raw imported JSON
  /// (see docs/PRD.md section 4 for the expected shape). Does not validate —
  /// validation happens separately so all errors can be collected at once.
  factory Question.fromJson(Map<String, dynamic> json, String questionSetId) {
    return Question(
      id: '',
      questionSetId: questionSetId,
      sourceId: json['id']?.toString(),
      questionText: json['question'] as String? ?? '',
      options: (json['options'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      correctAnswer: json['correct_answer'] is int
          ? json['correct_answer'] as int
          : int.tryParse(json['correct_answer']?.toString() ?? '') ?? -1,
      explanation: json['explanation'] as String?,
      topic: json['topic'] as String?,
      difficulty: json['difficulty'] as String?,
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'question_set_id': questionSetId,
      if (sourceId != null) 'source_id': sourceId,
      'question_text': questionText,
      'options': options,
      'correct_answer': correctAnswer,
      if (explanation != null) 'explanation': explanation,
      if (topic != null) 'topic': topic,
      if (difficulty != null) 'difficulty': difficulty,
    };
  }
}

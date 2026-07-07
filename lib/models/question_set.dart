class QuestionSet {
  final String id;
  final String folderId;
  final String title;
  final String? subject;
  final num defaultMarksPerCorrect;
  final num defaultNegativeMarksPerWrong;
  final DateTime createdAt;

  const QuestionSet({
    required this.id,
    required this.folderId,
    required this.title,
    this.subject,
    this.defaultMarksPerCorrect = 1,
    this.defaultNegativeMarksPerWrong = 0,
    required this.createdAt,
  });

  factory QuestionSet.fromMap(Map<String, dynamic> map) {
    return QuestionSet(
      id: map['id'] as String,
      folderId: map['folder_id'] as String,
      title: map['title'] as String,
      subject: map['subject'] as String?,
      defaultMarksPerCorrect: (map['default_marks_per_correct'] as num?) ?? 1,
      defaultNegativeMarksPerWrong:
          (map['default_negative_marks_per_wrong'] as num?) ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'folder_id': folderId,
      'title': title,
      if (subject != null) 'subject': subject,
      'default_marks_per_correct': defaultMarksPerCorrect,
      'default_negative_marks_per_wrong': defaultNegativeMarksPerWrong,
    };
  }
}

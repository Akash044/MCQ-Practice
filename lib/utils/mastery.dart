import '../models/attempt_answer.dart';
import '../models/question.dart';

/// Implements the wrong-answer / skipped pool derivation and mastery rule
/// defined in docs/PRD.md section 6 ("Derived views") and section 9
/// ("Mastery rule"). No new tables — computed client-side from the full
/// attempt_answers history of a question set.
class QuestionPools {
  static const defaultMasteryStreak = 2;

  static Map<String, List<AttemptAnswer>> _byQuestion(List<AttemptAnswer> answers) {
    final map = <String, List<AttemptAnswer>>{};
    for (final a in answers) {
      map.putIfAbsent(a.questionId, () => []).add(a);
    }
    return map;
  }

  /// True once the last [masteryStreak] non-skipped answers for a question
  /// are all correct.
  static bool isMastered(
    List<AttemptAnswer> answersForQuestion, {
    int masteryStreak = defaultMasteryStreak,
  }) {
    final nonSkipped = answersForQuestion.where((a) => a.status != AnswerStatus.skipped).toList()
      ..sort((a, b) => a.answeredAt.compareTo(b.answeredAt));
    if (nonSkipped.length < masteryStreak) return false;
    return nonSkipped.reversed.take(masteryStreak).every((a) => a.status == AnswerStatus.correct);
  }

  /// Questions whose most recent non-skipped answer is incorrect and not yet
  /// mastered.
  static List<Question> wrongPool(
    List<Question> questions,
    List<AttemptAnswer> allAnswers, {
    int masteryStreak = defaultMasteryStreak,
  }) {
    final byQuestion = _byQuestion(allAnswers);
    return questions.where((q) {
      final answers = byQuestion[q.id];
      if (answers == null || answers.isEmpty) return false;
      final nonSkipped = answers.where((a) => a.status != AnswerStatus.skipped).toList()
        ..sort((a, b) => a.answeredAt.compareTo(b.answeredAt));
      if (nonSkipped.isEmpty) return false;
      return nonSkipped.last.status == AnswerStatus.incorrect &&
          !isMastered(answers, masteryStreak: masteryStreak);
    }).toList();
  }

  /// Questions whose most recent answer (of any status) was a skip.
  static List<Question> skippedPool(List<Question> questions, List<AttemptAnswer> allAnswers) {
    final byQuestion = _byQuestion(allAnswers);
    return questions.where((q) {
      final answers = byQuestion[q.id];
      if (answers == null || answers.isEmpty) return false;
      final sorted = [...answers]..sort((a, b) => a.answeredAt.compareTo(b.answeredAt));
      return sorted.last.status == AnswerStatus.skipped;
    }).toList();
  }
}

import 'attempt.dart';

class ExamConfig {
  final AttemptMode mode;
  final AttemptSourceType sourceType;
  final String? topicFilter;
  final String? difficultyFilter;
  final num marksPerCorrect;
  final num negativeMarksPerWrong;
  final int? examTimerMinutes;
  final int? perQuestionTimerSeconds;
  final bool shuffleQuestions;
  final bool shuffleOptions;

  const ExamConfig({
    required this.mode,
    required this.sourceType,
    this.topicFilter,
    this.difficultyFilter,
    required this.marksPerCorrect,
    required this.negativeMarksPerWrong,
    this.examTimerMinutes,
    this.perQuestionTimerSeconds,
    this.shuffleQuestions = true,
    this.shuffleOptions = true,
  });
}

import 'exam_config.dart';
import 'question.dart';

/// A question within a running exam, with its display-order option
/// permutation (so option shuffling doesn't require remapping
/// `correct_answer`) and the answer recorded so far, if any.
class RunnerQuestion {
  final Question question;
  final List<int> optionOrder;
  final int? selectedOriginalIndex;
  final int? timeTakenSeconds;

  const RunnerQuestion({
    required this.question,
    required this.optionOrder,
    this.selectedOriginalIndex,
    this.timeTakenSeconds,
  });

  bool get isAnswered => selectedOriginalIndex != null;
  bool get isCorrect => selectedOriginalIndex == question.correctAnswer;

  RunnerQuestion copyWith({int? selectedOriginalIndex, int? timeTakenSeconds}) {
    return RunnerQuestion(
      question: question,
      optionOrder: optionOrder,
      selectedOriginalIndex:
          selectedOriginalIndex ?? this.selectedOriginalIndex,
      timeTakenSeconds: timeTakenSeconds ?? this.timeTakenSeconds,
    );
  }
}

class ExamSessionState {
  final ExamConfig config;
  final List<RunnerQuestion> questions;
  final int currentIndex;
  final DateTime startedAt;
  final DateTime? examEndTime;
  final DateTime? questionEndTime;
  final bool submitted;

  const ExamSessionState({
    required this.config,
    required this.questions,
    required this.currentIndex,
    required this.startedAt,
    this.examEndTime,
    this.questionEndTime,
    this.submitted = false,
  });

  RunnerQuestion get current => questions[currentIndex];
  bool get isLast => currentIndex == questions.length - 1;

  int get correctCount =>
      questions.where((q) => q.isAnswered && q.isCorrect).length;
  int get wrongCount =>
      questions.where((q) => q.isAnswered && !q.isCorrect).length;
  int get skippedCount => questions.where((q) => !q.isAnswered).length;
  num get totalScore =>
      correctCount * config.marksPerCorrect -
      wrongCount * config.negativeMarksPerWrong;

  Duration? get examRemaining => examEndTime?.difference(DateTime.now());
  Duration? get questionRemaining =>
      questionEndTime?.difference(DateTime.now());

  ExamSessionState copyWith({
    List<RunnerQuestion>? questions,
    int? currentIndex,
    DateTime? examEndTime,
    DateTime? questionEndTime,
    bool clearQuestionEndTime = false,
    bool? submitted,
  }) {
    return ExamSessionState(
      config: config,
      questions: questions ?? this.questions,
      currentIndex: currentIndex ?? this.currentIndex,
      startedAt: startedAt,
      examEndTime: examEndTime ?? this.examEndTime,
      questionEndTime: clearQuestionEndTime
          ? null
          : (questionEndTime ?? this.questionEndTime),
      submitted: submitted ?? this.submitted,
    );
  }
}

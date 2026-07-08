import '../models/question.dart';

class QuestionValidationError {
  final int index;
  final String? sourceId;
  final String message;

  const QuestionValidationError({
    required this.index,
    this.sourceId,
    required this.message,
  });

  @override
  String toString() =>
      'Question #${index + 1}${sourceId != null ? ' (id: $sourceId)' : ''}: $message';
}

class QuestionSetValidationResult {
  final String? examTitle;
  final String? subject;
  final List<Question> validQuestions;
  final List<QuestionValidationError> errors;

  const QuestionSetValidationResult({
    required this.examTitle,
    required this.subject,
    required this.validQuestions,
    required this.errors,
  });

  bool get isValid => errors.isEmpty && validQuestions.isNotEmpty;
}

/// Validates a list of raw question JSON objects against the schema in
/// docs/PRD.md section 4, collecting every error instead of throwing on the
/// first one so callers can show what's wrong per-question (PRD section
/// 5.1: "don't silently drop them"). Shared by [QuestionSetValidator.validate]
/// (a whole exam-set import) and anywhere else that just needs to validate a
/// batch of questions (e.g. adding more questions to an existing set).
class QuestionListValidationResult {
  final List<Question> validQuestions;
  final List<QuestionValidationError> errors;

  const QuestionListValidationResult({
    required this.validQuestions,
    required this.errors,
  });

  bool get isValid => errors.isEmpty && validQuestions.isNotEmpty;
}

QuestionListValidationResult validateQuestionList(
  List<dynamic> rawQuestions, {
  required String questionSetId,
}) {
  final errors = <QuestionValidationError>[];
  final valid = <Question>[];
  final seenIds = <String>{};

  for (var i = 0; i < rawQuestions.length; i++) {
    final raw = rawQuestions[i];
    if (raw is! Map<String, dynamic>) {
      errors.add(
        QuestionValidationError(
          index: i,
          message: 'Question is not a JSON object.',
        ),
      );
      continue;
    }

    final sourceId = raw['id']?.toString();
    final questionMessages = <String>[];

    final questionText = raw['question'];
    if (questionText is! String || questionText.trim().isEmpty) {
      questionMessages.add('Missing or empty "question" text.');
    }

    final options = raw['options'];
    if (options is! List || options.length < 2) {
      questionMessages.add(
        '"options" must be a list with at least 2 entries.',
      );
    }

    final correctAnswerRaw = raw['correct_answer'];
    int? correctAnswer;
    if (correctAnswerRaw is int) {
      correctAnswer = correctAnswerRaw;
    } else if (correctAnswerRaw is String) {
      correctAnswer = int.tryParse(correctAnswerRaw);
    }
    if (correctAnswer == null) {
      questionMessages.add('"correct_answer" must be an integer index.');
    } else if (options is List &&
        (correctAnswer < 0 || correctAnswer >= options.length)) {
      questionMessages.add(
        '"correct_answer" index $correctAnswer is out of range for ${options.length} options.',
      );
    }

    if (sourceId != null && sourceId.isNotEmpty) {
      if (seenIds.contains(sourceId)) {
        questionMessages.add('Duplicate question id "$sourceId".');
      } else {
        seenIds.add(sourceId);
      }
    }

    if (questionMessages.isNotEmpty) {
      errors.add(
        QuestionValidationError(
          index: i,
          sourceId: sourceId,
          message: questionMessages.join(' '),
        ),
      );
      continue;
    }

    valid.add(Question.fromJson(raw, questionSetId));
  }

  return QuestionListValidationResult(validQuestions: valid, errors: errors);
}

class QuestionSetValidator {
  static QuestionSetValidationResult validate(Map<String, dynamic> json) {
    final examTitle = json['exam_title'] as String?;
    final subject = json['subject'] as String?;
    final rawQuestions = json['questions'];

    final errors = <QuestionValidationError>[];

    if (examTitle == null || examTitle.trim().isEmpty) {
      errors.add(
        const QuestionValidationError(
          index: -1,
          message: 'Missing required field "exam_title" at top level.',
        ),
      );
    }

    if (rawQuestions is! List || rawQuestions.isEmpty) {
      errors.add(
        const QuestionValidationError(
          index: -1,
          message: 'Missing or empty "questions" array.',
        ),
      );
      return QuestionSetValidationResult(
        examTitle: examTitle,
        subject: subject,
        validQuestions: const [],
        errors: errors,
      );
    }

    final result = validateQuestionList(rawQuestions, questionSetId: '');
    return QuestionSetValidationResult(
      examTitle: examTitle,
      subject: subject,
      validQuestions: result.validQuestions,
      errors: [...errors, ...result.errors],
    );
  }
}

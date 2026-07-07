import '../models/attempt.dart';
import '../models/attempt_answer.dart';
import '../models/question.dart';

class TopicAccuracy {
  final String topic;
  final int correct;
  final int wrong;

  const TopicAccuracy({
    required this.topic,
    required this.correct,
    required this.wrong,
  });

  int get total => correct + wrong;
  double get accuracy => total == 0 ? 0 : correct / total;
}

class WeakSpot {
  final Question question;
  final int correct;
  final int wrong;

  const WeakSpot({
    required this.question,
    required this.correct,
    required this.wrong,
  });

  int get total => correct + wrong;
  double get wrongRate => total == 0 ? 0 : wrong / total;
}

class StreakInfo {
  final int daysPracticed;
  final int currentStreak;

  const StreakInfo({required this.daysPracticed, required this.currentStreak});
}

/// Analytics derived from an attempt/attempt_answer history, per the rules in
/// docs/PRD.md section 6 ("Derived views") and section 9 (retry attempts are
/// excluded from trend/topic charts but still count toward mastery streaks).
class ProgressStats {
  /// Attempts eligible for trend/topic-accuracy charts — retry drilling
  /// (`wrong_answers_retry`/`skipped_retry`) is excluded so it doesn't
  /// artificially inflate "improvement" stats.
  static List<Attempt> trendAttempts(List<Attempt> attempts) {
    final eligible =
        attempts.where((a) => a.sourceType.countsTowardTrendCharts).toList()
          ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return eligible;
  }

  /// Accuracy (0-100) per trend-eligible attempt, in chronological order —
  /// feeds the trend line chart.
  static List<double> accuracyTrend(List<Attempt> attempts) {
    return trendAttempts(attempts).map((a) {
      final answered = a.correctCount + a.wrongCount;
      return answered == 0 ? 0.0 : a.correctCount / answered * 100;
    }).toList();
  }

  /// Per-topic accuracy, computed only from trend-eligible attempts.
  static List<TopicAccuracy> topicAccuracy(
    List<AttemptAnswer> answers,
    Map<String, Attempt> attemptById,
    Map<String, Question> questionById,
  ) {
    final byTopic = <String, TopicAccuracy>{};
    for (final answer in answers) {
      if (answer.status == AnswerStatus.skipped) continue;
      final attempt = attemptById[answer.attemptId];
      if (attempt == null || !attempt.sourceType.countsTowardTrendCharts) {
        continue;
      }
      final topic = questionById[answer.questionId]?.topic;
      if (topic == null) continue;

      final existing = byTopic[topic];
      final isCorrect = answer.status == AnswerStatus.correct;
      byTopic[topic] = TopicAccuracy(
        topic: topic,
        correct: (existing?.correct ?? 0) + (isCorrect ? 1 : 0),
        wrong: (existing?.wrong ?? 0) + (isCorrect ? 0 : 1),
      );
    }
    final result = byTopic.values.toList()
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    return result;
  }

  /// Questions with a wrong rate at/above [threshold] across *all* attempts
  /// (unlike the trend/topic views, this isn't restricted to full_set/custom
  /// — section 6 defines "per-question wrong rate" without that filter),
  /// sorted worst-first. Requires at least [minAttempts] non-skipped answers
  /// so a single unlucky guess doesn't dominate the list.
  static List<WeakSpot> weakSpots(
    List<AttemptAnswer> answers,
    Map<String, Question> questionById, {
    double threshold = 0.4,
    int minAttempts = 2,
  }) {
    final byQuestion = <String, WeakSpot>{};
    for (final answer in answers) {
      if (answer.status == AnswerStatus.skipped) continue;
      final question = questionById[answer.questionId];
      if (question == null) continue;

      final existing = byQuestion[question.id];
      final isCorrect = answer.status == AnswerStatus.correct;
      byQuestion[question.id] = WeakSpot(
        question: question,
        correct: (existing?.correct ?? 0) + (isCorrect ? 1 : 0),
        wrong: (existing?.wrong ?? 0) + (isCorrect ? 0 : 1),
      );
    }
    final result =
        byQuestion.values
            .where((w) => w.total >= minAttempts && w.wrongRate >= threshold)
            .toList()
          ..sort((a, b) => b.wrongRate.compareTo(a.wrongRate));
    return result;
  }

  /// Days-practiced count and current daily streak, based on the distinct
  /// calendar dates of any attempt (any source_type — consistency of
  /// practice, not accuracy, is what a streak measures).
  static StreakInfo streak(List<Attempt> attempts) {
    final days = attempts.map((a) {
      final d = a.startedAt;
      return DateTime(d.year, d.month, d.day);
    }).toSet();

    if (days.isEmpty) {
      return const StreakInfo(daysPracticed: 0, currentStreak: 0);
    }

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    var cursor = days.contains(todayDate)
        ? todayDate
        : todayDate.subtract(const Duration(days: 1));

    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return StreakInfo(daysPracticed: days.length, currentStreak: streak);
  }
}

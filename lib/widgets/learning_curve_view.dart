import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../models/attempt.dart';
import '../models/attempt_answer.dart';
import '../models/folder.dart';
import '../models/question.dart';
import '../models/question_set.dart';
import '../providers/supabase_providers.dart';
import '../screens/exam/exam_setup_screen.dart';
import '../utils/network_error.dart';
import '../utils/progress_stats.dart';

/// Streak/trend/topic/weak-spot/history breakdown shared by the single-exam
/// [ProgressScreen] and a subfolder's aggregated learning curve — the
/// [ProgressStats] calculations are already generic over any attempt/answer/
/// question list, so this widget only adds the per-attempt "which exam is
/// this" lookup ([setById]) needed to navigate a retry or label a history
/// card when the attempts span more than one exam.
class LearningCurveView extends ConsumerWidget {
  const LearningCurveView({
    super.key,
    required this.folder,
    required this.attempts,
    required this.answers,
    required this.questions,
    required this.setById,
    required this.onAttemptDeleted,
    this.showExamLabel = false,
  });

  final Folder folder;
  final List<Attempt> attempts;
  final List<AttemptAnswer> answers;
  final List<Question> questions;
  final Map<String, QuestionSet> setById;
  final VoidCallback onAttemptDeleted;
  final bool showExamLabel;

  void _retry(
    BuildContext context,
    Attempt attempt,
    AttemptSourceType sourceType,
    Set<String> questionIds,
  ) {
    final set = setById[attempt.questionSetId];
    if (set == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExamSetupScreen(
          folder: folder,
          questionSet: set,
          initialSourceType: sourceType,
          preselectedQuestionIds: questionIds,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Attempt attempt,
  ) async {
    final confirmed = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        title: const Text('Delete this attempt?'),
        body: const Text(
          'This removes it (and its answers) from your history. This cannot be undone.',
        ),
        actions: [
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FButton(
            variant: FButtonVariant.destructive,
            onPress: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await withConnectivityCheck(
        () => ref.read(supabaseServiceProvider).deleteAttempt(attempt.id),
      );
      onAttemptDeleted();
    } catch (e) {
      if (context.mounted) {
        showFToast(
          context: context,
          variant: FToastVariant.destructive,
          title: Text(
            e is NoInternetException
                ? 'No internet connection'
                : 'Could not delete attempt',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (attempts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No attempts yet. Take an exam to start tracking progress.',
        ),
      );
    }

    final questionById = {for (final q in questions) q.id: q};
    final attemptById = {for (final a in attempts) a.id: a};
    final trend = ProgressStats.accuracyTrend(attempts);
    final topicAccuracy = ProgressStats.topicAccuracy(
      answers,
      attemptById,
      questionById,
    );
    final weakSpots = ProgressStats.weakSpots(answers, questionById);
    final streak = ProgressStats.streak(attempts);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FBadge(child: Text('${streak.currentStreak}-day streak')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FBadge(
                variant: FBadgeVariant.secondary,
                child: Text('${streak.daysPracticed} days practiced'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FBadge(
                variant: FBadgeVariant.secondary,
                child: Text('${attempts.length} attempts'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Accuracy trend', style: context.theme.typography.sm),
        const SizedBox(height: 8),
        if (trend.length < 2)
          const Text('Take at least two full-set attempts to see a trend.')
        else
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 100,
                titlesData: const FlTitlesData(
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 32),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    spots: [
                      for (var i = 0; i < trend.length; i++)
                        FlSpot(i.toDouble(), trend[i]),
                    ],
                    dotData: const FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        if (topicAccuracy.isNotEmpty) ...[
          Text('By topic', style: context.theme.typography.sm),
          const SizedBox(height: 8),
          for (final t in topicAccuracy)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t.topic} · ${(t.accuracy * 100).round()}% (${t.correct}/${t.total})',
                  ),
                  const SizedBox(height: 4),
                  FDeterminateProgress(value: t.accuracy),
                ],
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (weakSpots.isNotEmpty) ...[
          Text('Persistent weak spots', style: context.theme.typography.sm),
          const SizedBox(height: 8),
          FTileGroup(
            children: [
              for (final w in weakSpots)
                FTile(
                  title: Text(
                    w.question.questionText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'Wrong ${(w.wrongRate * 100).round()}% of ${w.total} attempts',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        Text('History', style: context.theme.typography.sm),
        const SizedBox(height: 8),
        for (final a in attempts) _buildAttemptCard(context, ref, a),
      ],
    );
  }

  Widget _buildAttemptCard(BuildContext context, WidgetRef ref, Attempt a) {
    final attemptAnswers = answers.where((ans) => ans.attemptId == a.id);
    final wrongIds = attemptAnswers
        .where((ans) => ans.status == AnswerStatus.incorrect)
        .map((ans) => ans.questionId)
        .toSet();
    final skippedIds = attemptAnswers
        .where((ans) => ans.status == AnswerStatus.skipped)
        .map((ans) => ans.questionId)
        .toSet();
    final examTitle = setById[a.questionSetId]?.title;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FCard(
        title: Text('${a.startedAt.toLocal()}'.split('.').first),
        subtitle: Text(
          '${showExamLabel && examTitle != null ? '$examTitle · ' : ''}'
          '${a.sourceType.value} · ${a.mode.value} · score ${a.totalScore ?? 0}'
          ' · ${a.durationSeconds ?? 0}s',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Correct ${a.correctCount} · Wrong ${a.wrongCount} · Skipped ${a.skippedCount}',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (wrongIds.isNotEmpty)
                  Expanded(
                    child: FButton(
                      variant: FButtonVariant.outline,
                      size: FButtonSizeVariant.sm,
                      prefix: const Icon(FIcons.rotateCcw),
                      onPress: () => _retry(
                        context,
                        a,
                        AttemptSourceType.wrongAnswersRetry,
                        wrongIds,
                      ),
                      child: Text('Retry wrong (${wrongIds.length})'),
                    ),
                  ),
                if (wrongIds.isNotEmpty && skippedIds.isNotEmpty)
                  const SizedBox(width: 8),
                if (skippedIds.isNotEmpty)
                  Expanded(
                    child: FButton(
                      variant: FButtonVariant.outline,
                      size: FButtonSizeVariant.sm,
                      prefix: const Icon(FIcons.rotateCcw),
                      onPress: () => _retry(
                        context,
                        a,
                        AttemptSourceType.skippedRetry,
                        skippedIds,
                      ),
                      child: Text('Retry skipped (${skippedIds.length})'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FButton(
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                prefix: const Icon(FIcons.trash2),
                onPress: () => _confirmDelete(context, ref, a),
                child: const Text('Delete attempt'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/attempt.dart';
import '../../models/attempt_answer.dart';
import '../../models/folder.dart';
import '../../models/question.dart';
import '../../models/question_set.dart';
import '../../providers/exam_providers.dart';
import '../../providers/supabase_providers.dart';
import '../../utils/network_error.dart';
import '../../utils/progress_stats.dart';
import '../../widgets/error_state.dart';
import '../exam/exam_setup_screen.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key, required this.folder, required this.questionSet});

  final Folder folder;
  final QuestionSet questionSet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attemptsAsync = ref.watch(attemptHistoryProvider(questionSet.id));
    final answersAsync = ref.watch(answersForSetProvider(questionSet.id));
    final questionsAsync = ref.watch(questionsForSetProvider(questionSet.id));

    return FScaffold(
      header: FHeader.nested(
        title: Text('${questionSet.title} · Progress'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.pop(context))],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: attemptsAsync.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (err, stack) =>
              ErrorState(error: err, label: 'Failed to load attempts'),
          data: (attempts) {
            if (attempts.isEmpty) {
              return const Center(
                child: Text(
                  'No attempts yet. Take an exam to start tracking progress.',
                ),
              );
            }
            return answersAsync.when(
              loading: () => const Center(child: FCircularProgress()),
              error: (err, stack) =>
                  ErrorState(error: err, label: 'Failed to load answers'),
              data: (answers) => questionsAsync.when(
                loading: () => const Center(child: FCircularProgress()),
                error: (err, stack) =>
                    ErrorState(error: err, label: 'Failed to load questions'),
                data: (questions) =>
                    _buildBody(context, ref, attempts, answers, questions),
              ),
            );
          },
        ),
      ),
    );
  }

  void _retry(
    BuildContext context,
    AttemptSourceType sourceType,
    Set<String> questionIds,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExamSetupScreen(
          folder: folder,
          questionSet: questionSet,
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
      ref.invalidate(attemptHistoryProvider(questionSet.id));
      ref.invalidate(answersForSetProvider(questionSet.id));
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

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<Attempt> attempts,
    List<AttemptAnswer> answers,
    List<Question> questions,
  ) {
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

    return ListView(
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
        for (final a in attempts)
          _buildAttemptCard(context, ref, a, answers),
      ],
    );
  }

  Widget _buildAttemptCard(
    BuildContext context,
    WidgetRef ref,
    Attempt a,
    List<AttemptAnswer> answers,
  ) {
    final attemptAnswers = answers.where((ans) => ans.attemptId == a.id);
    final wrongIds = attemptAnswers
        .where((ans) => ans.status == AnswerStatus.incorrect)
        .map((ans) => ans.questionId)
        .toSet();
    final skippedIds = attemptAnswers
        .where((ans) => ans.status == AnswerStatus.skipped)
        .map((ans) => ans.questionId)
        .toSet();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FCard(
        title: Text('${a.startedAt.toLocal()}'.split('.').first),
        subtitle: Text(
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

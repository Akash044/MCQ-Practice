import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/attempt.dart';
import '../../models/folder.dart';
import '../../models/question.dart';
import '../../models/question_set.dart';
import '../../providers/exam_providers.dart';
import '../../utils/mastery.dart';
import '../exam/exam_setup_screen.dart';

enum BankPoolType { wrong, skipped }

/// Browses the current wrong-answer or skipped pool for a set (docs/PRD.md
/// section 5.5), filterable by topic/difficulty, with a shortcut into exam
/// setup pre-loaded with this exact source + filters.
class QuestionBankScreen extends ConsumerStatefulWidget {
  const QuestionBankScreen({
    super.key,
    required this.folder,
    required this.questionSet,
    required this.poolType,
  });

  final Folder folder;
  final QuestionSet questionSet;
  final BankPoolType poolType;

  @override
  ConsumerState<QuestionBankScreen> createState() => _QuestionBankScreenState();
}

class _QuestionBankScreenState extends ConsumerState<QuestionBankScreen> {
  String? _topicFilter;
  String? _difficultyFilter;

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(questionsForSetProvider(widget.questionSet.id));
    final answersAsync = ref.watch(answersForSetProvider(widget.questionSet.id));

    return FScaffold(
      header: FHeader.nested(
        title: Text(widget.poolType == BankPoolType.wrong ? 'Wrong answer bank' : 'Skipped bank'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.pop(context))],
      ),
      child: questionsAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (err, stack) => Center(child: Text('Failed to load questions: $err')),
        data: (questions) => answersAsync.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (err, stack) => Center(child: Text('Failed to load attempt history: $err')),
          data: (answers) {
            final pool = widget.poolType == BankPoolType.wrong
                ? QuestionPools.wrongPool(questions, answers)
                : QuestionPools.skippedPool(questions, answers);

            final topics = pool.map((q) => q.topic).whereType<String>().toSet().toList()..sort();
            final difficulties = pool.map((q) => q.difficulty).whereType<String>().toSet().toList()..sort();

            final filtered = pool.where((q) {
              if (_topicFilter != null && q.topic != _topicFilter) return false;
              if (_difficultyFilter != null && q.difficulty != _difficultyFilter) return false;
              return true;
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (topics.isNotEmpty || difficulties.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        if (topics.isNotEmpty)
                          Expanded(
                            child: FSelect<String?>(
                              hint: 'All topics',
                              items: {'All topics': null, for (final t in topics) t: t},
                              control: FSelectControl.managed(
                                initial: _topicFilter,
                                onChange: (v) => setState(() => _topicFilter = v),
                              ),
                            ),
                          ),
                        if (topics.isNotEmpty && difficulties.isNotEmpty) const SizedBox(width: 12),
                        if (difficulties.isNotEmpty)
                          Expanded(
                            child: FSelect<String?>(
                              hint: 'All difficulties',
                              items: {'All difficulties': null, for (final d in difficulties) d: d},
                              control: FSelectControl.managed(
                                initial: _difficultyFilter,
                                onChange: (v) => setState(() => _difficultyFilter = v),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('Nothing here right now.'))
                      : FTileGroup(
                          children: [
                            for (final q in filtered)
                              FTile(
                                title: Text(q.questionText, maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: _subtitle(q),
                              ),
                          ],
                        ),
                ),
                if (filtered.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  FButton(
                    prefix: const Icon(FIcons.play),
                    onPress: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ExamSetupScreen(
                          folder: widget.folder,
                          questionSet: widget.questionSet,
                          initialSourceType: widget.poolType == BankPoolType.wrong
                              ? AttemptSourceType.wrongAnswersRetry
                              : AttemptSourceType.skippedRetry,
                          initialTopicFilter: _topicFilter,
                          initialDifficultyFilter: _difficultyFilter,
                        ),
                      ),
                    ),
                    child: Text('Start exam with these ${filtered.length} questions'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget? _subtitle(Question q) {
    if (q.topic == null && q.difficulty == null) return null;
    return Text([q.topic, q.difficulty].whereType<String>().join(' · '));
  }
}

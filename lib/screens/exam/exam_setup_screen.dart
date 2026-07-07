import 'package:flutter/material.dart' show MaterialPageRoute, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/attempt.dart';
import '../../models/attempt_answer.dart';
import '../../models/exam_config.dart';
import '../../models/folder.dart';
import '../../models/question.dart';
import '../../models/question_set.dart';
import '../../providers/exam_providers.dart';
import '../../providers/exam_session_notifier.dart';
import '../../utils/mastery.dart';
import '../progress/progress_screen.dart';
import 'exam_runner_screen.dart';

class ExamSetupScreen extends ConsumerStatefulWidget {
  const ExamSetupScreen({
    super.key,
    required this.folder,
    required this.questionSet,
    this.initialSourceType = AttemptSourceType.fullSet,
  });

  final Folder folder;
  final QuestionSet questionSet;

  /// Lets the results screen jump here with "Wrong answers" or "Skipped"
  /// pre-selected instead of always defaulting to the full set.
  final AttemptSourceType initialSourceType;

  @override
  ConsumerState<ExamSetupScreen> createState() => _ExamSetupScreenState();
}

class _ExamSetupScreenState extends ConsumerState<ExamSetupScreen> {
  AttemptMode _mode = AttemptMode.practice;
  late AttemptSourceType _sourceType = widget.initialSourceType;
  String? _topicFilter;
  String? _difficultyFilter;
  bool _shuffleQuestions = true;
  bool _shuffleOptions = true;

  bool _examTimerEnabled = false;
  bool _perQuestionTimerEnabled = false;

  late final TextEditingController _marksController;
  late final TextEditingController _negativeMarksController;
  final _examMinutesController = TextEditingController(text: '60');
  final _perQuestionSecondsController = TextEditingController(text: '45');

  @override
  void initState() {
    super.initState();
    _marksController = TextEditingController(text: '${widget.questionSet.defaultMarksPerCorrect}');
    _negativeMarksController =
        TextEditingController(text: '${widget.questionSet.defaultNegativeMarksPerWrong}');
  }

  @override
  void dispose() {
    _marksController.dispose();
    _negativeMarksController.dispose();
    _examMinutesController.dispose();
    _perQuestionSecondsController.dispose();
    super.dispose();
  }

  void _start(List<Question> allQuestions, List<AttemptAnswer> allAnswers) {
    List<Question> base;
    switch (_sourceType) {
      case AttemptSourceType.fullSet:
      case AttemptSourceType.custom:
        base = allQuestions;
      case AttemptSourceType.wrongAnswersRetry:
        base = QuestionPools.wrongPool(allQuestions, allAnswers);
      case AttemptSourceType.skippedRetry:
        base = QuestionPools.skippedPool(allQuestions, allAnswers);
    }

    final filtered = base.where((q) {
      if (_topicFilter != null && q.topic != _topicFilter) return false;
      if (_difficultyFilter != null && q.difficulty != _difficultyFilter) return false;
      return true;
    }).toList();

    if (filtered.isEmpty) {
      showFToast(
        context: context,
        variant: FToastVariant.destructive,
        title: const Text('No questions match'),
        description: const Text('Try a different source or clear your filters.'),
      );
      return;
    }

    final effectiveSourceType =
        _sourceType == AttemptSourceType.fullSet && (_topicFilter != null || _difficultyFilter != null)
            ? AttemptSourceType.custom
            : _sourceType;

    final config = ExamConfig(
      mode: _mode,
      sourceType: effectiveSourceType,
      topicFilter: _topicFilter,
      difficultyFilter: _difficultyFilter,
      marksPerCorrect: num.tryParse(_marksController.text) ?? widget.questionSet.defaultMarksPerCorrect,
      negativeMarksPerWrong:
          num.tryParse(_negativeMarksController.text) ?? widget.questionSet.defaultNegativeMarksPerWrong,
      examTimerMinutes: _examTimerEnabled ? int.tryParse(_examMinutesController.text) : null,
      perQuestionTimerSeconds:
          _perQuestionTimerEnabled ? int.tryParse(_perQuestionSecondsController.text) : null,
      shuffleQuestions: _shuffleQuestions,
      shuffleOptions: _shuffleOptions,
    );

    ref.read(examSessionProvider.notifier).start(questions: filtered, config: config);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ExamRunnerScreen(folder: widget.folder, questionSet: widget.questionSet),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(questionsForSetProvider(widget.questionSet.id));
    final answersAsync = ref.watch(answersForSetProvider(widget.questionSet.id));

    return FScaffold(
      header: FHeader.nested(
        title: Text(widget.questionSet.title),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.pop(context))],
        suffixes: [
          FHeaderAction(
            icon: const Icon(FIcons.chartLine),
            onPress: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ProgressScreen(questionSet: widget.questionSet)),
            ),
          ),
        ],
      ),
      child: questionsAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (err, stack) => Center(child: Text('Failed to load questions: $err')),
        data: (questions) {
          if (questions.isEmpty) {
            return const Center(child: Text('This set has no questions.'));
          }
          return answersAsync.when(
            loading: () => const Center(child: FCircularProgress()),
            error: (err, stack) => Center(child: Text('Failed to load attempt history: $err')),
            data: (answers) => _buildForm(questions, answers),
          );
        },
      ),
    );
  }

  Widget _buildForm(List<Question> questions, List<AttemptAnswer> answers) {
    final wrongCount = QuestionPools.wrongPool(questions, answers).length;
    final skippedCount = QuestionPools.skippedPool(questions, answers).length;

    final topics = questions.map((q) => q.topic).whereType<String>().toSet().toList()..sort();
    final difficulties = questions.map((q) => q.difficulty).whereType<String>().toSet().toList()..sort();

    return ListView(
      children: [
        Text('Mode', style: context.theme.typography.sm),
        const SizedBox(height: 8),
        FTileGroup(
          children: [
            FTile(
              title: const Text('Practice (instant feedback)'),
              selected: _mode == AttemptMode.practice,
              onPress: () => setState(() => _mode = AttemptMode.practice),
            ),
            FTile(
              title: const Text('Test (score at the end)'),
              selected: _mode == AttemptMode.test,
              onPress: () => setState(() => _mode = AttemptMode.test),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Source', style: context.theme.typography.sm),
        const SizedBox(height: 8),
        FTileGroup(
          children: [
            FTile(
              title: Text('Full set (${questions.length})'),
              selected: _sourceType == AttemptSourceType.fullSet,
              onPress: () => setState(() => _sourceType = AttemptSourceType.fullSet),
            ),
            FTile(
              title: Text('Wrong answers ($wrongCount)'),
              enabled: wrongCount > 0,
              selected: _sourceType == AttemptSourceType.wrongAnswersRetry,
              onPress: () => setState(() => _sourceType = AttemptSourceType.wrongAnswersRetry),
            ),
            FTile(
              title: Text('Skipped questions ($skippedCount)'),
              enabled: skippedCount > 0,
              selected: _sourceType == AttemptSourceType.skippedRetry,
              onPress: () => setState(() => _sourceType = AttemptSourceType.skippedRetry),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (topics.isNotEmpty) ...[
          FSelect<String?>(
            label: const Text('Topic filter'),
            hint: 'All topics',
            items: {'All topics': null, for (final t in topics) t: t},
            control: FSelectControl.managed(
              initial: _topicFilter,
              onChange: (v) => setState(() => _topicFilter = v),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (difficulties.isNotEmpty) ...[
          FSelect<String?>(
            label: const Text('Difficulty filter'),
            hint: 'All difficulties',
            items: {'All difficulties': null, for (final d in difficulties) d: d},
            control: FSelectControl.managed(
              initial: _difficultyFilter,
              onChange: (v) => setState(() => _difficultyFilter = v),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: FTextField(
                label: const Text('Marks per correct'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                control: FTextFieldControl.managed(controller: _marksController),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FTextField(
                label: const Text('Negative per wrong'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                control: FTextFieldControl.managed(controller: _negativeMarksController),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FSwitch(
          label: const Text('Exam timer'),
          value: _examTimerEnabled,
          onChange: (v) => setState(() => _examTimerEnabled = v),
        ),
        if (_examTimerEnabled)
          FTextField(
            label: const Text('Total minutes'),
            keyboardType: TextInputType.number,
            control: FTextFieldControl.managed(controller: _examMinutesController),
          ),
        const SizedBox(height: 12),
        FSwitch(
          label: const Text('Per-question timer'),
          value: _perQuestionTimerEnabled,
          onChange: (v) => setState(() => _perQuestionTimerEnabled = v),
        ),
        if (_perQuestionTimerEnabled)
          FTextField(
            label: const Text('Seconds per question'),
            keyboardType: TextInputType.number,
            control: FTextFieldControl.managed(controller: _perQuestionSecondsController),
          ),
        const SizedBox(height: 12),
        FSwitch(
          label: const Text('Shuffle question order'),
          value: _shuffleQuestions,
          onChange: (v) => setState(() => _shuffleQuestions = v),
        ),
        FSwitch(
          label: const Text('Shuffle answer options'),
          value: _shuffleOptions,
          onChange: (v) => setState(() => _shuffleOptions = v),
        ),
        const SizedBox(height: 20),
        FButton(
          onPress: () => _start(questions, answers),
          child: const Text('Start exam'),
        ),
      ],
    );
  }
}

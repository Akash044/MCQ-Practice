import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/question.dart';
import '../../models/question_set.dart';
import '../../providers/exam_providers.dart';
import '../../providers/supabase_providers.dart';
import '../../utils/network_error.dart';
import '../../widgets/error_state.dart';

/// Lets an existing exam's question list be edited directly — adding new
/// questions by hand and deleting ones that no longer belong — without
/// having to re-import the whole set as JSON.
class ManageQuestionsScreen extends ConsumerWidget {
  const ManageQuestionsScreen({super.key, required this.questionSet});

  final QuestionSet questionSet;

  Future<void> _addQuestion(BuildContext context, WidgetRef ref) async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => _AddQuestionScreen(questionSet: questionSet),
      ),
    );
    if (added == true) {
      ref.invalidate(questionsForSetProvider(questionSet.id));
    }
  }

  Future<void> _deleteQuestion(
    BuildContext context,
    WidgetRef ref,
    Question question,
  ) async {
    final confirmed = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        title: const Text('Delete this question?'),
        body: const Text(
          'This also removes any recorded answers for it. This cannot be undone.',
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
        () => ref.read(supabaseServiceProvider).deleteQuestion(question.id),
      );
      ref.invalidate(questionsForSetProvider(questionSet.id));
    } catch (e) {
      if (context.mounted) {
        showFToast(
          context: context,
          variant: FToastVariant.destructive,
          title: Text(
            e is NoInternetException
                ? 'No internet connection'
                : 'Could not delete question',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questionsAsync = ref.watch(questionsForSetProvider(questionSet.id));

    return FScaffold(
      header: FHeader.nested(
        title: Text('Manage · ${questionSet.title}'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.pop(context))],
        suffixes: [
          FHeaderAction(
            icon: const Icon(FIcons.plus),
            onPress: () => _addQuestion(context, ref),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: questionsAsync.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (err, stack) =>
              ErrorState(error: err, label: 'Failed to load questions'),
          data: (questions) {
            if (questions.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No questions in this exam yet.'),
                    const SizedBox(height: 12),
                    FButton(
                      prefix: const Icon(FIcons.plus),
                      onPress: () => _addQuestion(context, ref),
                      child: const Text('Add a question'),
                    ),
                  ],
                ),
              );
            }
            return ListView(
              children: [
                Text(
                  '${questions.length} question${questions.length == 1 ? '' : 's'}',
                  style: context.theme.typography.sm,
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < questions.length; i++)
                  _buildQuestionCard(context, ref, i, questions[i]),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildQuestionCard(
    BuildContext context,
    WidgetRef ref,
    int index,
    Question q,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FCard(
        title: Text('Q${index + 1}. ${q.questionText}'),
        subtitle: [
          q.topic,
          q.difficulty,
        ].whereType<String>().join(' · ').isEmpty
            ? null
            : Text([q.topic, q.difficulty].whereType<String>().join(' · ')),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < q.options.length; i++)
              Text(
                '${i == q.correctAnswer ? '✓ ' : '  '}${q.options[i]}',
                style: i == q.correctAnswer
                    ? const TextStyle(fontWeight: FontWeight.w600)
                    : null,
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FButton(
                variant: FButtonVariant.destructive,
                size: FButtonSizeVariant.sm,
                prefix: const Icon(FIcons.trash2),
                onPress: () => _deleteQuestion(context, ref, q),
                child: const Text('Delete'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple hand-entry form for a single question, reusing the same fields
/// JSON import supports (docs/PRD.md section 4) minus source_id.
class _AddQuestionScreen extends ConsumerStatefulWidget {
  const _AddQuestionScreen({required this.questionSet});

  final QuestionSet questionSet;

  @override
  ConsumerState<_AddQuestionScreen> createState() =>
      _AddQuestionScreenState();
}

class _AddQuestionScreenState extends ConsumerState<_AddQuestionScreen> {
  final _questionController = TextEditingController();
  final _explanationController = TextEditingController();
  final _topicController = TextEditingController();
  final _difficultyController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  int _correctAnswer = 0;
  bool _saving = false;

  @override
  void dispose() {
    _questionController.dispose();
    _explanationController.dispose();
    _topicController.dispose();
    _difficultyController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int index) {
    setState(() {
      _optionControllers.removeAt(index).dispose();
      if (_correctAnswer >= _optionControllers.length) {
        _correctAnswer = _optionControllers.length - 1;
      }
    });
  }

  Future<void> _save() async {
    final questionText = _questionController.text.trim();
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (questionText.isEmpty) {
      showFToast(
        context: context,
        variant: FToastVariant.destructive,
        title: const Text('Enter the question text'),
      );
      return;
    }
    if (options.length < 2) {
      showFToast(
        context: context,
        variant: FToastVariant.destructive,
        title: const Text('Enter at least 2 non-empty options'),
      );
      return;
    }
    if (_correctAnswer < 0 || _correctAnswer >= options.length) {
      showFToast(
        context: context,
        variant: FToastVariant.destructive,
        title: const Text('Pick a valid correct answer'),
      );
      return;
    }

    setState(() => _saving = true);
    final question = Question(
      id: '',
      questionSetId: widget.questionSet.id,
      questionText: questionText,
      options: options,
      correctAnswer: _correctAnswer,
      explanation: _explanationController.text.trim().isEmpty
          ? null
          : _explanationController.text.trim(),
      topic: _topicController.text.trim().isEmpty
          ? null
          : _topicController.text.trim(),
      difficulty: _difficultyController.text.trim().isEmpty
          ? null
          : _difficultyController.text.trim(),
      createdAt: DateTime.now(),
    );

    try {
      await withConnectivityCheck(
        () => ref.read(supabaseServiceProvider).addQuestion(question),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        showFToast(
          context: context,
          variant: FToastVariant.destructive,
          title: Text(
            e is NoInternetException
                ? 'No internet connection'
                : 'Could not save question',
          ),
          description: e is NoInternetException ? null : Text('$e'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: FHeader.nested(
        title: const Text('Add question'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.pop(context))],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: ListView(
          children: [
            FTextField(
              label: const Text('Question'),
              maxLines: 3,
              control: FTextFieldControl.managed(
                controller: _questionController,
              ),
            ),
            const SizedBox(height: 12),
            Text('Options', style: context.theme.typography.sm),
            const SizedBox(height: 4),
            Text(
              'Tap the circle next to the correct option.',
              style: context.theme.typography.xs,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _optionControllers.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    FRadio(
                      value: _correctAnswer == i,
                      onChange: (_) => setState(() => _correctAnswer = i),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FTextField(
                        hint: 'Option ${i + 1}',
                        control: FTextFieldControl.managed(
                          controller: _optionControllers[i],
                        ),
                      ),
                    ),
                    if (_optionControllers.length > 2)
                      FButton(
                        variant: FButtonVariant.ghost,
                        size: FButtonSizeVariant.sm,
                        onPress: () => _removeOption(i),
                        child: const Icon(FIcons.x),
                      ),
                  ],
                ),
              ),
            FButton(
              variant: FButtonVariant.ghost,
              prefix: const Icon(FIcons.plus),
              onPress: _addOption,
              child: const Text('Add option'),
            ),
            const SizedBox(height: 12),
            FTextField(
              label: const Text('Explanation (optional)'),
              maxLines: 2,
              control: FTextFieldControl.managed(
                controller: _explanationController,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FTextField(
                    label: const Text('Topic (optional)'),
                    control: FTextFieldControl.managed(
                      controller: _topicController,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FTextField(
                    label: const Text('Difficulty (optional)'),
                    control: FTextFieldControl.managed(
                      controller: _difficultyController,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FButton(
              onPress: _saving ? null : _save,
              prefix: _saving ? const FCircularProgress() : null,
              child: const Text('Save question'),
            ),
          ],
        ),
      ),
    );
  }
}

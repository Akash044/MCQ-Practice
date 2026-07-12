import 'dart:convert';

import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/question.dart';
import '../../models/question_set.dart';
import '../../providers/exam_providers.dart';
import '../../providers/supabase_providers.dart';
import '../../utils/network_error.dart';
import '../../utils/question_set_validator.dart';
import '../../widgets/error_state.dart';

/// Shown to the user (and copyable) so they can hand it to an AI/LLM as the
/// exact format to generate for new questions — same per-question shape as
/// the full JSON import (see import_screen.dart's `jsonFormatExample`) minus
/// the exam-level wrapper, since these are being added to an existing set.
const _questionJsonFormatExample = '''
[
  {
    "question": "What is the SI unit of dynamic viscosity?",
    "options": ["Pa", "Pa·s", "N/m", "m²/s"],
    "correct_answer": 1,
    "explanation": "Dynamic viscosity is measured in Pascal-seconds (Pa·s).",
    "topic": "Viscosity",
    "difficulty": "medium"
  }
]''';

/// Lets an existing exam's question list be edited directly — pasting more
/// questions in as JSON, and deleting ones that no longer belong — without
/// having to re-import the whole set from scratch.
class ManageQuestionsScreen extends ConsumerWidget {
  const ManageQuestionsScreen({super.key, required this.questionSet});

  final QuestionSet questionSet;

  Future<void> _addQuestions(BuildContext context, WidgetRef ref) async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => _AddQuestionsScreen(questionSet: questionSet),
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
          description: e is NoInternetException ? null : Text('$e'),
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
            onPress: () => _addQuestions(context, ref),
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
                      onPress: () => _addQuestions(context, ref),
                      child: const Text('Add questions'),
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

/// Adds one or more questions to an existing exam by pasting JSON — the same
/// per-question shape the full-set import accepts (docs/PRD.md section 4),
/// either as a single object or an array of several.
class _AddQuestionsScreen extends ConsumerStatefulWidget {
  const _AddQuestionsScreen({required this.questionSet});

  final QuestionSet questionSet;

  @override
  ConsumerState<_AddQuestionsScreen> createState() =>
      _AddQuestionsScreenState();
}

class _AddQuestionsScreenState extends ConsumerState<_AddQuestionsScreen> {
  final _jsonController = TextEditingController();
  QuestionListValidationResult? _result;
  String? _parseError;
  bool _showFormat = false;
  bool _saving = false;

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final clip = await Clipboard.getData('text/plain');
      if (clip?.text != null) {
        _jsonController.text = clip!.text!;
        _validate(clip.text!);
      }
    } catch (_) {
      // Clipboard access can fail on some platforms; the text field is still
      // editable manually.
    }
  }

  void _validate(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _parseError = null;
        _result = null;
      });
      return;
    }
    try {
      final decoded = jsonDecode(trimmed);
      final rawList = decoded is List ? decoded : [decoded];
      setState(() {
        _parseError = null;
        _result = validateQuestionList(
          rawList,
          questionSetId: widget.questionSet.id,
        );
      });
    } catch (e) {
      setState(() {
        _parseError = 'Failed to parse JSON: $e';
        _result = null;
      });
    }
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null || !result.isValid) return;

    setState(() => _saving = true);
    try {
      await withConnectivityCheck(
        () => ref
            .read(supabaseServiceProvider)
            .addQuestions(result.validQuestions),
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
                : 'Could not save questions',
          ),
          description: e is NoInternetException ? null : Text('$e'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return FScaffold(
      header: FHeader.nested(
        title: const Text('Add questions'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.pop(context))],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: ListView(
          children: [
            FTextField(
              label: const Text('Question JSON'),
              hint: 'Paste one question object, or an array of several',
              maxLines: 10,
              control: FTextFieldControl.managed(
                controller: _jsonController,
                onChange: (v) => _validate(v.text),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FButton(
                    variant: FButtonVariant.outline,
                    prefix: const Icon(FIcons.clipboardPaste),
                    onPress: _pasteFromClipboard,
                    child: const Text('Paste from clipboard'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FButton(
                    variant: FButtonVariant.ghost,
                    prefix: const Icon(FIcons.braces),
                    onPress: () => setState(() => _showFormat = !_showFormat),
                    child: Text(_showFormat ? 'Hide format' : 'View format'),
                  ),
                ),
              ],
            ),
            if (_showFormat) ...[
              const SizedBox(height: 8),
              _buildFormatCard(context),
            ],
            const SizedBox(height: 16),
            if (_parseError != null)
              FAlert(
                variant: FAlertVariant.destructive,
                title: const Text('Could not read JSON'),
                subtitle: Text(_parseError!),
              ),
            if (result != null) ...[
              Text(
                '${result.validQuestions.length} valid question(s), '
                '${result.errors.length} error(s)',
              ),
              if (result.errors.isNotEmpty) ...[
                const SizedBox(height: 8),
                FTileGroup(
                  children: [
                    for (final e in result.errors)
                      FTile(
                        prefix: const Icon(FIcons.circleAlert),
                        title: Text(e.toString()),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
            ],
            FButton(
              onPress: (result?.isValid ?? false) && !_saving ? _save : null,
              prefix: _saving ? const FCircularProgress() : null,
              child: Text(
                result == null
                    ? 'Paste JSON above to continue'
                    : result.isValid
                    ? 'Add ${result.validQuestions.length} question'
                          '${result.validQuestions.length == 1 ? '' : 's'}'
                    : 'Fix errors before adding',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatCard(BuildContext context) {
    return FCard(
      title: const Text('Expected JSON format'),
      subtitle: const Text(
        'Paste this to an AI along with your source material and ask it to '
        'fill it in. A single question object (not wrapped in an array) '
        'also works. "explanation", "topic", and "difficulty" are optional.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Text(
                _questionJsonFormatExample,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FButton(
            variant: FButtonVariant.outline,
            prefix: const Icon(FIcons.copy),
            onPress: () async {
              await Clipboard.setData(
                const ClipboardData(text: _questionJsonFormatExample),
              );
              if (context.mounted) {
                showFToast(
                  context: context,
                  title: const Text('Copied to clipboard'),
                );
              }
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }
}

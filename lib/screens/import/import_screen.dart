import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/folder.dart';
import '../../providers/supabase_providers.dart';
import '../../utils/network_error.dart';
import '../../utils/question_set_validator.dart';

/// Shown to the user (and copyable) so they can hand it to an AI/LLM as the
/// exact format to generate — kept in sync with QuestionSetValidator's rules
/// and docs/PRD.md section 4. `id`, `explanation`, `topic`, and `difficulty`
/// are optional; everything else is required.
const jsonFormatExample = '''
{
  "exam_title": "Fluid Dynamics - Chapter 3",
  "subject": "Fluid Dynamics",
  "questions": [
    {
      "id": "q1",
      "question": "What is the SI unit of dynamic viscosity?",
      "options": ["Pa", "Pa·s", "N/m", "m²/s"],
      "correct_answer": 1,
      "explanation": "Dynamic viscosity is measured in Pascal-seconds (Pa·s).",
      "topic": "Viscosity",
      "difficulty": "medium"
    }
  ]
}''';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, required this.folder});

  final Folder folder;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  String? _fileName;
  QuestionSetValidationResult? _result;
  bool _loading = false;
  bool _importing = false;
  String? _loadError;
  bool _showFormat = false;

  Future<void> _processJsonText(String text, {String? fileName}) async {
    setState(() {
      _loading = true;
      _loadError = null;
      _result = null;
    });

    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw Exception(
          'Top-level JSON must be an object (see docs/PRD.md section 4).',
        );
      }

      final result = QuestionSetValidator.validate(decoded);
      setState(() {
        if (fileName != null) _fileName = fileName;
        _result = result;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = 'Failed to parse JSON: $e';
        _loading = false;
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() => _loadError = 'Could not read file contents.');
        return;
      }

      await _processJsonText(utf8.decode(bytes), fileName: file.name);
    } catch (e) {
      setState(() => _loadError = 'Failed to read file: $e');
    }
  }

  Future<void> _pasteJson() async {
    final controller = TextEditingController();
    try {
      final clip = await Clipboard.getData('text/plain');
      if (clip?.text != null) controller.text = clip!.text!;
    } catch (_) {
      // Clipboard access can fail on some platforms; just start with an empty box.
    }

    if (!mounted) return;
    final text = await showFDialog<String>(
      context: context,
      builder: (context, style, animation) => FDialog(
        title: const Text('Paste JSON'),
        body: SizedBox(
          width: double.maxFinite,
          child: FTextField(
            autofocus: true,
            maxLines: 10,
            hint: 'Paste your question set JSON here',
            control: FTextFieldControl.managed(controller: controller),
          ),
        ),
        actions: [
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FButton(
            onPress: () => Navigator.pop(context, controller.text),
            child: const Text('Use this text'),
          ),
        ],
      ),
    );

    if (text == null || text.trim().isEmpty) return;
    await _processJsonText(text);
  }

  Future<void> _confirmImport() async {
    final result = _result;
    if (result == null || !result.isValid) return;

    setState(() => _importing = true);
    try {
      await withConnectivityCheck(
        () => ref
            .read(supabaseServiceProvider)
            .importQuestionSet(
              folderId: widget.folder.id,
              title: result.examTitle ?? _fileName ?? 'Untitled set',
              subject: result.subject,
              questions: result.validQuestions,
            ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _importing = false);
      if (mounted) {
        showFToast(
          context: context,
          variant: FToastVariant.destructive,
          title: Text(
            e is NoInternetException
                ? 'No internet connection'
                : 'Import failed',
          ),
          description: e is NoInternetException
              ? const Text('Check your connection and try again.')
              : Text('$e'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return FScaffold(
      header: FHeader.nested(
        title: Text('Import into ${widget.folder.name}'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.pop(context))],
      ),
      // top: false — the header already safe-areas itself against the status
      // bar/notch; this keeps the "Import N questions" button clear of the
      // gesture nav bar.
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FButton(
                    onPress: _loading ? null : _pickFile,
                    prefix: const Icon(FIcons.fileUp),
                    child: Text(_fileName ?? 'Choose .json file'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FButton(
                    variant: FButtonVariant.outline,
                    onPress: _loading ? null : _pasteJson,
                    prefix: const Icon(FIcons.clipboardPaste),
                    child: const Text('Paste JSON'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FButton(
              variant: FButtonVariant.ghost,
              prefix: const Icon(FIcons.braces),
              onPress: () => setState(() => _showFormat = !_showFormat),
              child: Text(
                _showFormat ? 'Hide JSON format' : 'View JSON format',
              ),
            ),
            if (_showFormat) ...[
              const SizedBox(height: 8),
              _buildFormatCard(context),
            ],
            const SizedBox(height: 16),
            if (_loading) const Center(child: FCircularProgress()),
            if (_loadError != null)
              FAlert(
                variant: FAlertVariant.destructive,
                title: const Text('Could not read JSON'),
                subtitle: Text(_loadError!),
              ),
            if (result != null) Expanded(child: _buildResult(context, result)),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatCard(BuildContext context) {
    return FCard(
      title: const Text('Expected JSON format'),
      subtitle: const Text(
        'Paste this to an AI along with your source material and ask it to fill it in.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Text(
                jsonFormatExample,
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
                const ClipboardData(text: jsonFormatExample),
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

  Widget _buildResult(
    BuildContext context,
    QuestionSetValidationResult result,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${result.validQuestions.length} valid question(s), ${result.errors.length} error(s)',
        ),
        const SizedBox(height: 8),
        Expanded(
          child: result.errors.isEmpty
              ? const SizedBox.shrink()
              : SingleChildScrollView(
                  child: FTileGroup(
                    children: [
                      for (final e in result.errors)
                        FTile(
                          prefix: const Icon(FIcons.circleAlert),
                          title: Text(e.toString()),
                        ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 8),
        FButton(
          onPress: result.isValid && !_importing ? _confirmImport : null,
          prefix: _importing ? const FCircularProgress() : null,
          child: Text(
            result.isValid
                ? 'Import ${result.validQuestions.length} questions'
                : 'Fix errors before importing',
          ),
        ),
      ],
    );
  }
}

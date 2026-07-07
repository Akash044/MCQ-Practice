import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/folder.dart';
import '../../providers/supabase_providers.dart';
import '../../utils/question_set_validator.dart';

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

  Future<void> _pickFile() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _result = null;
    });

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('Could not read file contents.');
      }

      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Top-level JSON must be an object (see docs/PRD.md section 4).');
      }

      final result = QuestionSetValidator.validate(decoded);
      setState(() {
        _fileName = file.name;
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

  Future<void> _confirmImport() async {
    final result = _result;
    if (result == null || !result.isValid) return;

    setState(() => _importing = true);
    try {
      await ref.read(supabaseServiceProvider).importQuestionSet(
            folderId: widget.folder.id,
            title: result.examTitle ?? _fileName ?? 'Untitled set',
            subject: result.subject,
            questions: result.validQuestions,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _importing = false);
      if (mounted) {
        showFToast(
          context: context,
          variant: FToastVariant.destructive,
          title: Text('Import failed: $e'),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FButton(
            onPress: _loading ? null : _pickFile,
            prefix: const Icon(FIcons.fileUp),
            child: Text(_fileName ?? 'Choose .json file'),
          ),
          const SizedBox(height: 16),
          if (_loading) const Center(child: FCircularProgress()),
          if (_loadError != null)
            FAlert(
              variant: FAlertVariant.destructive,
              title: const Text('Could not read file'),
              subtitle: Text(_loadError!),
            ),
          if (result != null) Expanded(child: _buildResult(context, result)),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context, QuestionSetValidationResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${result.validQuestions.length} valid question(s), ${result.errors.length} error(s)'),
        const SizedBox(height: 8),
        Expanded(
          child: result.errors.isEmpty
              ? const SizedBox.shrink()
              : FTileGroup(
                  children: [
                    for (final e in result.errors)
                      FTile(
                        prefix: const Icon(FIcons.circleAlert),
                        title: Text(e.toString()),
                      ),
                  ],
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

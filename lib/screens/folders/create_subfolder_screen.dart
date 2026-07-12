import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/folder.dart';
import '../../models/question_set.dart';
import '../../providers/supabase_providers.dart';
import '../../utils/network_error.dart';

/// Creates a chapter-like subfolder under [parentFolder] and, optionally,
/// moves whichever of the parent's existing exams the user picks into it. An
/// exam belongs to exactly one folder at a time, so picking it here reassigns
/// it rather than linking it to two places — it will no longer show up in
/// the parent folder's own exam list afterwards.
class CreateSubfolderScreen extends ConsumerStatefulWidget {
  const CreateSubfolderScreen({
    super.key,
    required this.parentFolder,
    required this.availableExams,
  });

  final Folder parentFolder;
  final List<QuestionSet> availableExams;

  @override
  ConsumerState<CreateSubfolderScreen> createState() =>
      _CreateSubfolderScreenState();
}

class _CreateSubfolderScreenState
    extends ConsumerState<CreateSubfolderScreen> {
  final _nameController = TextEditingController();
  final Set<String> _selectedSetIds = {};
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _toggle(String setId) {
    setState(() {
      if (!_selectedSetIds.remove(setId)) _selectedSetIds.add(setId);
    });
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showFToast(
        context: context,
        variant: FToastVariant.destructive,
        title: const Text('Give the subfolder a name'),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final service = ref.read(supabaseServiceProvider);
      await withConnectivityCheck(() async {
        final subfolder = await service.createFolder(
          name,
          parentId: widget.parentFolder.id,
        );
        if (_selectedSetIds.isNotEmpty) {
          await service.moveQuestionSetsToFolder(
            _selectedSetIds.toList(),
            subfolder.id,
          );
        }
      });
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
                : 'Could not create subfolder',
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
        title: const Text('New Subfolder'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.pop(context))],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: ListView(
          children: [
            FTextField(
              label: const Text('Name'),
              hint: 'e.g. Chapter 1 - Algebra',
              autofocus: true,
              control: FTextFieldControl.managed(controller: _nameController),
            ),
            const SizedBox(height: 16),
            if (widget.availableExams.isNotEmpty) ...[
              Text(
                'Move exams into this subfolder',
                style: context.theme.typography.sm,
              ),
              const SizedBox(height: 4),
              Text(
                'Optional — you can move exams in later too. An exam only lives in one place at a time.',
                style: context.theme.typography.xs,
              ),
              const SizedBox(height: 8),
              for (final set in widget.availableExams)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: FCheckbox(
                    value: _selectedSetIds.contains(set.id),
                    onChange: (_) => _toggle(set.id),
                    label: Text(set.title),
                  ),
                ),
              const SizedBox(height: 16),
            ],
            FButton(
              onPress: _saving ? null : _create,
              prefix: _saving ? const FCircularProgress() : null,
              child: const Text('Create subfolder'),
            ),
          ],
        ),
      ),
    );
  }
}

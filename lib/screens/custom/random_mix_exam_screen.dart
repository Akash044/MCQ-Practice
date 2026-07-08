import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/folder.dart';
import '../../models/question.dart';
import '../../models/question_set.dart';
import '../../providers/question_set_providers.dart';
import '../../providers/supabase_providers.dart';
import '../../utils/network_error.dart';
import '../../utils/random_mix.dart';
import '../../widgets/error_state.dart';
import 'custom_exam_builder_screen.dart' show customFolderName;

/// Picks questions randomly across several existing exams (possibly from
/// different folders), split as evenly as possible per exam, to build one
/// new exam of a target size — saved under the shared "Custom" folder.
class RandomMixExamScreen extends ConsumerStatefulWidget {
  const RandomMixExamScreen({super.key});

  @override
  ConsumerState<RandomMixExamScreen> createState() =>
      _RandomMixExamScreenState();
}

class _RandomMixExamScreenState extends ConsumerState<RandomMixExamScreen> {
  final Set<String> _selectedSetIds = {};
  final _totalController = TextEditingController();
  final _titleController = TextEditingController(text: 'Random Mix Exam');
  bool _saving = false;

  @override
  void dispose() {
    _totalController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _toggle(String setId) {
    setState(() {
      if (!_selectedSetIds.remove(setId)) _selectedSetIds.add(setId);
    });
  }

  Future<void> _create() async {
    final title = _titleController.text.trim();
    final total = int.tryParse(_totalController.text.trim());

    if (_selectedSetIds.isEmpty) {
      showFToast(
        context: context,
        variant: FToastVariant.destructive,
        title: const Text('Select at least one exam'),
      );
      return;
    }
    if (total == null || total <= 0) {
      showFToast(
        context: context,
        variant: FToastVariant.destructive,
        title: const Text('Enter a valid total question count'),
      );
      return;
    }
    if (title.isEmpty) {
      showFToast(
        context: context,
        variant: FToastVariant.destructive,
        title: const Text('Give this exam a title'),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final service = ref.read(supabaseServiceProvider);
      final mixed = await withConnectivityCheck(() async {
        final questionsBySetId = <String, List<Question>>{};
        for (final setId in _selectedSetIds) {
          questionsBySetId[setId] = await service.fetchQuestions(setId);
        }
        final result = evenRandomMix(questionsBySetId, total);
        if (result.isEmpty) {
          throw Exception('Selected exams have no questions.');
        }
        final customFolder = await service.findOrCreateFolder(customFolderName);
        await service.importQuestionSet(
          folderId: customFolder.id,
          title: title,
          questions: result,
        );
        return result;
      });

      if (mounted && mixed.length < total) {
        showFToast(
          context: context,
          title: Text(
            'Only ${mixed.length} of $total questions were available',
          ),
        );
      }

      ref.invalidate(foldersProvider);
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
                : 'Could not create exam',
          ),
          description: e is NoInternetException ? null : Text('$e'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSetsAsync = ref.watch(allQuestionSetsWithFolderProvider);

    return FScaffold(
      header: FHeader.nested(
        title: const Text('Random Mix Exam'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.pop(context))],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: allSetsAsync.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (err, stack) =>
              ErrorState(error: err, label: 'Failed to load exams'),
          data: (allSets) {
            if (allSets.isEmpty) {
              return const Center(
                child: Text(
                  'Import a question set first, then come back here to build a mix.',
                ),
              );
            }

            final byFolder = <Folder, List<QuestionSet>>{};
            for (final (folder, set) in allSets) {
              byFolder.putIfAbsent(folder, () => []).add(set);
            }

            return ListView(
              children: [
                Text(
                  '${_selectedSetIds.length} exam(s) selected',
                  style: context.theme.typography.sm,
                ),
                const SizedBox(height: 8),
                for (final entry in byFolder.entries) ...[
                  Text(entry.key.name, style: context.theme.typography.sm),
                  const SizedBox(height: 4),
                  for (final set in entry.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: FCheckbox(
                        value: _selectedSetIds.contains(set.id),
                        onChange: (_) => _toggle(set.id),
                        label: Text(set.title),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                FTextField(
                  label: const Text('Total questions'),
                  hint: 'e.g. 100',
                  keyboardType: TextInputType.number,
                  control: FTextFieldControl.managed(
                    controller: _totalController,
                  ),
                ),
                const SizedBox(height: 12),
                FTextField(
                  label: const Text('Custom exam title'),
                  control: FTextFieldControl.managed(
                    controller: _titleController,
                  ),
                ),
                const SizedBox(height: 16),
                FButton(
                  onPress: _saving ? null : _create,
                  prefix: _saving ? const FCircularProgress() : null,
                  child: const Text('Create random mix exam'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

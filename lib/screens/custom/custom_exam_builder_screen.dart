import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/question.dart';
import '../../providers/exam_providers.dart';
import '../../providers/question_set_providers.dart';
import '../../providers/supabase_providers.dart';
import '../../utils/network_error.dart';
import '../../widgets/error_state.dart';

const customFolderName = 'Custom';

/// Builds a new question set by hand-picking questions out of an existing
/// set (folder → set → questions), then saves it as a fresh question_set
/// under a "Custom" folder (auto-created on first use) — a copy, not a
/// reference, consistent with how JSON import already works.
class CustomExamBuilderScreen extends ConsumerStatefulWidget {
  const CustomExamBuilderScreen({super.key});

  @override
  ConsumerState<CustomExamBuilderScreen> createState() =>
      _CustomExamBuilderScreenState();
}

class _CustomExamBuilderScreenState
    extends ConsumerState<CustomExamBuilderScreen> {
  String? _folderId;
  String? _setId;
  final Set<String> _selectedQuestionIds = {};
  final _titleController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _pickFolder(String? folderId) {
    setState(() {
      _folderId = folderId;
      _setId = null;
      _selectedQuestionIds.clear();
    });
  }

  void _pickSet(String? setId, String setTitle) {
    setState(() {
      _setId = setId;
      _selectedQuestionIds.clear();
      _titleController.text = '$setTitle (Custom)';
    });
  }

  void _toggleQuestion(String questionId) {
    setState(() {
      if (!_selectedQuestionIds.remove(questionId)) {
        _selectedQuestionIds.add(questionId);
      }
    });
  }

  Future<void> _create(List<Question> allQuestions) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      showFToast(
        context: context,
        variant: FToastVariant.destructive,
        title: const Text('Give this exam a title'),
      );
      return;
    }
    if (_selectedQuestionIds.isEmpty) {
      showFToast(
        context: context,
        variant: FToastVariant.destructive,
        title: const Text('Select at least one question'),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final selected = allQuestions
          .where((q) => _selectedQuestionIds.contains(q.id))
          .toList();
      final service = ref.read(supabaseServiceProvider);
      await withConnectivityCheck(() async {
        final customFolder = await service.findOrCreateFolder(customFolderName);
        await service.importQuestionSet(
          folderId: customFolder.id,
          title: title,
          questions: selected,
        );
      });
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
                : 'Could not save exam',
          ),
          description: e is NoInternetException ? null : Text('$e'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(foldersProvider);

    return FScaffold(
      header: FHeader.nested(
        title: const Text('Create Custom Exam'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.pop(context))],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: foldersAsync.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (err, stack) =>
              ErrorState(error: err, label: 'Failed to load folders'),
          data: (folders) {
            if (folders.isEmpty) {
              return const Center(
                child: Text(
                  'Import a question set first, then come back here to build a custom exam.',
                ),
              );
            }
            return ListView(
              children: [
                Text('Folder', style: context.theme.typography.sm),
                const SizedBox(height: 8),
                FSelect<String>(
                  hint: 'Choose a folder',
                  items: {for (final f in folders) f.name: f.id},
                  control: FSelectControl.managed(
                    initial: _folderId,
                    onChange: _pickFolder,
                  ),
                ),
                if (_folderId != null) ...[
                  const SizedBox(height: 16),
                  Text('Exam', style: context.theme.typography.sm),
                  const SizedBox(height: 8),
                  Consumer(
                    builder: (context, ref, _) {
                      final setsAsync = ref.watch(
                        questionSetsProvider(_folderId!),
                      );
                      return setsAsync.when(
                        loading: () => const Center(child: FCircularProgress()),
                        error: (err, stack) => ErrorState(
                          error: err,
                          label: 'Failed to load exams',
                        ),
                        data: (sets) {
                          if (sets.isEmpty) {
                            return const Text('This folder has no exams yet.');
                          }
                          return FSelect<String>(
                            hint: 'Choose an exam',
                            items: {for (final s in sets) s.title: s.id},
                            control: FSelectControl.managed(
                              initial: _setId,
                              onChange: (id) {
                                if (id == null) return;
                                final set = sets.firstWhere((s) => s.id == id);
                                _pickSet(id, set.title);
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
                if (_setId != null) ...[
                  const SizedBox(height: 16),
                  Consumer(
                    builder: (context, ref, _) {
                      final questionsAsync = ref.watch(
                        questionsForSetProvider(_setId!),
                      );
                      return questionsAsync.when(
                        loading: () => const Center(child: FCircularProgress()),
                        error: (err, stack) => ErrorState(
                          error: err,
                          label: 'Failed to load questions',
                        ),
                        data: (questions) => _buildQuestionPicker(questions),
                      );
                    },
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildQuestionPicker(List<Question> questions) {
    final allSelected =
        questions.isNotEmpty && _selectedQuestionIds.length == questions.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_selectedQuestionIds.length} of ${questions.length} selected',
              style: context.theme.typography.sm,
            ),
            FButton(
              variant: FButtonVariant.ghost,
              onPress: () => setState(() {
                if (allSelected) {
                  _selectedQuestionIds.clear();
                } else {
                  _selectedQuestionIds
                    ..clear()
                    ..addAll(questions.map((q) => q.id));
                }
              }),
              child: Text(allSelected ? 'Deselect all' : 'Select all'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final q in questions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FCheckbox(
              value: _selectedQuestionIds.contains(q.id),
              onChange: (_) => _toggleQuestion(q.id),
              label: Text(q.questionText),
            ),
          ),
        const SizedBox(height: 8),
        FTextField(
          label: const Text('Custom exam title'),
          control: FTextFieldControl.managed(controller: _titleController),
        ),
        const SizedBox(height: 16),
        FButton(
          onPress: _saving ? null : () => _create(questions),
          prefix: _saving ? const FCircularProgress() : null,
          child: const Text('Create custom exam'),
        ),
      ],
    );
  }
}

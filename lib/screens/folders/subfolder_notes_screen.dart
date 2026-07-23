import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/folder.dart';
import '../../providers/supabase_providers.dart';
import '../../utils/network_error.dart';
import '../../utils/rich_text_notes.dart';

/// Full-screen rich-text editor for a subfolder's lecture notes — supports
/// bold, italic, color, quote, and numbered/bulleted lists. Pops with the
/// saved (JSON-encoded) notes on success (empty string if cleared/deleted),
/// or `null` if the user backs out without saving.
class SubfolderNotesScreen extends ConsumerStatefulWidget {
  const SubfolderNotesScreen({super.key, required this.folder});

  final Folder folder;

  @override
  ConsumerState<SubfolderNotesScreen> createState() =>
      _SubfolderNotesScreenState();
}

class _SubfolderNotesScreenState extends ConsumerState<SubfolderNotesScreen> {
  late final QuillController _controller = QuillController(
    document: documentFromNotes(widget.folder.notes),
    selection: const TextSelection.collapsed(offset: 0),
  );
  bool _saving = false;

  bool get _hasExistingNotes => (widget.folder.notes ?? '').isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final encoded = _controller.document.isEmpty()
        ? null
        : encodeNotesDocument(_controller.document);
    try {
      await withConnectivityCheck(
        () => ref
            .read(supabaseServiceProvider)
            .updateFolderNotes(widget.folder.id, encoded),
      );
      if (mounted) Navigator.pop(context, encoded ?? '');
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        showFToast(
          context: context,
          variant: FToastVariant.destructive,
          title: Text(
            e is NoInternetException
                ? 'No internet connection'
                : 'Could not save notes',
          ),
        );
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        title: const Text('Delete these notes?'),
        body: const Text("This can't be undone."),
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
    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      await withConnectivityCheck(
        () => ref
            .read(supabaseServiceProvider)
            .updateFolderNotes(widget.folder.id, null),
      );
      if (mounted) Navigator.pop(context, '');
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        showFToast(
          context: context,
          variant: FToastVariant.destructive,
          title: Text(
            e is NoInternetException
                ? 'No internet connection'
                : 'Could not delete notes',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: FHeader.nested(
        title: Text('Notes: ${widget.folder.name}'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.pop(context))],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A deliberately small subset of Quill's toolbar — just what was
            // asked for (bold, italic, color, quote, lists) rather than the
            // full default toolbar (headers, code blocks, alignment, etc.).
            QuillSimpleToolbar(
              controller: _controller,
              config: const QuillSimpleToolbarConfig(
                showDividers: false,
                showFontFamily: false,
                showFontSize: false,
                showBoldButton: true,
                showItalicButton: true,
                showSmallButton: false,
                showUnderLineButton: false,
                showStrikeThrough: false,
                showInlineCode: false,
                showColorButton: true,
                showBackgroundColorButton: false,
                showClearFormat: false,
                showAlignmentButtons: false,
                showHeaderStyle: false,
                showListNumbers: true,
                showListBullets: true,
                showListCheck: false,
                showCodeBlock: false,
                showQuote: true,
                showIndent: false,
                showLink: false,
                showUndo: true,
                showRedo: true,
                showSearchButton: false,
                showSubscript: false,
                showSuperscript: false,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: QuillEditor.basic(
                controller: _controller,
                config: const QuillEditorConfig(
                  placeholder: 'Write lecture notes for this subfolder…',
                  padding: EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_hasExistingNotes) ...[
                  Expanded(
                    child: FButton(
                      variant: FButtonVariant.destructive,
                      onPress: _saving ? null : _delete,
                      child: const Text('Delete'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FButton(
                    onPress: _saving ? null : _save,
                    prefix: _saving ? const FCircularProgress() : null,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

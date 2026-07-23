import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';

/// Subfolder lecture notes are persisted as JSON-encoded Quill Delta ops
/// (a list of `{"insert": ...}` maps), not plain text, so bold/italic/color/
/// list/quote formatting round-trips. These helpers convert between that
/// storage format and a [Document] — with a fallback for any notes saved
/// before rich text was added, when the column just held a plain string.
Document documentFromNotes(String? notes) {
  if (notes == null || notes.isEmpty) return Document();
  try {
    final decoded = jsonDecode(notes);
    if (decoded is List) return Document.fromJson(decoded);
  } catch (_) {
    // Not valid Delta JSON — fall through to the plain-text case below.
  }
  return Document.fromJson([
    {'insert': '$notes\n'},
  ]);
}

String encodeNotesDocument(Document document) =>
    jsonEncode(document.toDelta().toJson());

String notesPreviewText(String? notes) =>
    documentFromNotes(notes).toPlainText().trim();

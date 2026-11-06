// Note editor: autosave (debounced 800 ms), Read/Edit modes, inline Markdown
// styling while editing, tappable checklists, word count, attachments,
// pin/duplicate/move/delete with undo.
// Split across `note_editor_screen/` parts; this file stays the stable import
// path for callers and owns the public widget, its provider and the enums.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../../data/repositories/note_repository.dart';
import '../../settings/application/settings_providers.dart';
import '../../sync/application/pending_operations.dart';
import '../application/notes_providers.dart';
import 'markdown_editing_controller.dart' show MarkdownEditingController;
import 'markdown_preview.dart' show MarkdownPreview, countWords;

part 'note_editor_screen/state.dart';
part 'note_editor_screen/menu.dart';
part 'note_editor_screen/toolbar.dart';
part 'note_editor_screen/status_line.dart';
part 'note_editor_screen/links_section.dart';

enum _NoteMode { read, edit }

enum _SaveStatus { idle, saving, saved, failed }

final _noteProvider = StreamProvider.family<Note?, String>((ref, id) {
  return ref.watch(noteRepositoryProvider).watchNote(id);
});

class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

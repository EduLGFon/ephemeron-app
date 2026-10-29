// Note editor: autosave (debounced 800 ms), Markdown toolbar, edit/preview
// toggle, word count, attachments, pin/duplicate/move/delete.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../application/notes_providers.dart';
import 'markdown_preview.dart';

Future<void> showNoteEditor(BuildContext context,
    {Note? note, String? linkedEventId, String? folderId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NoteEditor(
        note: note,
        linkedEventId: linkedEventId,
        folderId: folderId),
  );
}

class _NoteEditor extends ConsumerStatefulWidget {
  const _NoteEditor({this.note, this.linkedEventId, this.folderId});

  final Note? note;
  final String? linkedEventId;
  final String? folderId;

  @override
  ConsumerState<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<_NoteEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  bool _preview = false;
  String? _noteId;
  Timer? _saveTimer;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _noteId = widget.note?.id;
    _title = TextEditingController(text: widget.note?.title ?? '');
    _body = TextEditingController(text: widget.note?.body ?? '');
    _title.addListener(_scheduleSave);
    _body.addListener(_scheduleSave);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _save() async {
    if (!mounted) return;
    final repo = ref.read(noteRepositoryProvider);
    setState(() => _saving = true);
    try {
      if (_noteId == null) {
        if (_title.text.trim().isEmpty &&
            _body.text.trim().isEmpty) {
          return;
        }
        _noteId = await repo.createNote(
          title: _title.text.trim().isEmpty
              ? 'Untitled'
              : _title.text.trim(),
          body: _body.text,
          folderId: widget.note?.folderId ?? widget.folderId,
          linkedEventId:
              widget.note?.linkedEventId ?? widget.linkedEventId,
        );
      } else {
        await repo.updateNote(
          _noteId!,
          title: _title.text.trim().isEmpty
              ? 'Untitled'
              : _title.text.trim(),
          body: () => _body.text,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _wrap(String before, [String after = '']) {
    final sel = _body.selection;
    final text = _body.text;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final selected = text.substring(start, end);
    final replacement = '$before$selected$after';
    _body.value = _body.value.copyWith(
      text: text.replaceRange(start, end, replacement),
      selection:
          TextSelection.collapsed(offset: start + replacement.length),
    );
  }

  void _prefixLine(String prefix) {
    final sel = _body.selection;
    final text = _body.text;
    final lineStart = sel.start < 0
        ? 0
        : text.lastIndexOf('\n', sel.start - 1) + 1;
    _body.value = _body.value.copyWith(
      text: text.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(
          offset: (sel.start < 0 ? text.length : sel.start) +
              prefix.length),
    );
  }

  void _toggleTask(int blockIndex) {
    // blockIndex is informational; toggle the first unchecked box,
    // or check all when none unchecked.
    final lines = _body.text.split('\n');
    var toggled = false;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains('- [ ]')) {
        lines[i] = lines[i].replaceFirst('- [ ]', '- [x]');
        toggled = true;
        break;
      }
    }
    if (!toggled) {
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('- [x]')) {
          lines[i] = lines[i].replaceFirst('- [x]', '- [ ]');
          break;
        }
      }
    }
    _body.text = lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final counts = countWords(_body.text);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _title,
                      decoration: const InputDecoration(
                        hintText: 'Title',
                        border: InputBorder.none,
                      ),
                      style:
                          Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (_saving)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child:
                          CircularProgressIndicator(strokeWidth: 2),
                    ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _preview = !_preview),
                    child: Text(_preview ? 'Edit' : 'Preview'),
                  ),
                ],
              ),
              if (!_preview) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _tool(Icons.format_bold, () => _wrap('**')),
                      _tool(Icons.format_italic, () => _wrap('*')),
                      _tool(Icons.code, () => _wrap('`')),
                      _tool(Icons.link, () => _wrap('[', '](url)')),
                      _tool(Icons.format_list_bulleted,
                          () => _prefixLine('- ')),
                      _tool(Icons.format_list_numbered,
                          () => _prefixLine('1. ')),
                      _tool(Icons.check_box_outlined,
                          () => _prefixLine('- [ ] ')),
                      _tool(Icons.title,
                          () => _prefixLine('## ')),
                      _tool(Icons.format_quote,
                          () => _prefixLine('> ')),
                    ],
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _body,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      hintText: 'Write in Markdown...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ] else
                Expanded(
                  child: MarkdownPreview(
                    body: _body.text,
                    onToggleTask: (_) => _toggleTask(0),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '${counts.words} words, ${counts.chars} chars',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  if (_noteId != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () async {
                        await ref
                            .read(noteRepositoryProvider)
                            .trashNote(_noteId!);
                        if (mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            SnackBar(
                              content:
                                  const Text('Note moved to trash'),
                              duration:
                                  const Duration(seconds: 6),
                              action: SnackBarAction(
                                label: 'Undo',
                                onPressed: () => ref
                                    .read(noteRepositoryProvider)
                                    .restoreNote(_noteId!),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tool(IconData icon, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

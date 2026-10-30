// Note editor: autosave (debounced 800 ms), Markdown toolbar,
// edit/preview toggle, tappable checklists, word count, attachments,
// pin/duplicate/move/delete with undo.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../../data/repositories/note_repository.dart';
import '../application/notes_providers.dart';
import 'markdown_preview.dart' show MarkdownPreview, countWords;

class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _titleCtl = TextEditingController();
  final _bodyCtl = TextEditingController();
  Timer? _saveTimer;
  bool _preview = false;
  bool _loaded = false;
  NoteRepository? _repo;

  @override
  void dispose() {
    _saveTimer?.cancel();
    // Never use ref after unmount: flush via the cached repository.
    final repo = _repo;
    if (_loaded && repo != null) {
      final id = widget.noteId;
      final title = _titleCtl.text;
      final body = _bodyCtl.text;
      unawaited(repo.updateNote(id, title: title, body: () => body));
    }
    _titleCtl.dispose();
    _bodyCtl.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _flush);
  }

  Future<void> _flush() async {
    final repo = _repo;
    if (!_loaded || repo == null) return;
    await repo.updateNote(
      widget.noteId,
      title: _titleCtl.text,
      body: () => _bodyCtl.text,
    );
  }

  void _toggleTask(int blockIndex) {
    final lines = _bodyCtl.text.split('\n');
    var seen = -1;
    for (var i = 0; i < lines.length; i++) {
      final m = RegExp(r'^(\s*-\s*\[)( |x|X)(\])').firstMatch(lines[i]);
      if (m != null) {
        seen++;
        if (seen == blockIndex) {
          final checked = m.group(2)!.toLowerCase() == 'x';
          lines[i] = lines[i].replaceFirst(
            m.group(0)!,
            '${m.group(1)}${checked ? ' ' : 'x'}${m.group(3)}',
          );
          _bodyCtl.text = lines.join('\n');
          _scheduleSave();
          setState(() {});
          return;
        }
      }
    }
  }

  void _wrap(String before, [String after = '']) {
    final sel = _bodyCtl.selection;
    final text = _bodyCtl.text;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final selected = text.substring(start, end);
    final replacement = '$before$selected$after';
    _bodyCtl.text = text.replaceRange(start, end, replacement);
    _bodyCtl.selection = TextSelection.collapsed(
      offset: start + replacement.length,
    );
    _scheduleSave();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final noteAsync = ref.watch(_noteProvider(widget.noteId));
    return noteAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Could not load note.')),
      ),
      data: (note) {
        if (note == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Note not found.')),
          );
        }
        if (!_loaded) {
          _loaded = true;
          _repo ??= ref.read(noteRepositoryProvider);
          _titleCtl.text = note.title;
          _bodyCtl.text = note.body ?? '';
          _titleCtl.addListener(_scheduleSave);
          _bodyCtl.addListener(_scheduleSave);
        }
        final counts = countWords(_bodyCtl.text);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Note'),
            actions: [
              IconButton(
                icon: Icon(
                  _preview ? Icons.edit_outlined : Icons.preview_outlined,
                ),
                tooltip: _preview ? 'Edit' : 'Preview',
                onPressed: () => setState(() => _preview = !_preview),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _menu(v, note),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'pin', child: Text('Pin / unpin')),
                  PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                  PopupMenuItem(value: 'move', child: Text('Move to folder')),
                  PopupMenuItem(
                    value: 'share',
                    child: Text('Share as Markdown'),
                  ),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _titleCtl,
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (!_preview) _Toolbar(onAction: _wrap),
              Expanded(
                child: _preview
                    ? MarkdownPreview(
                        body: _bodyCtl.text,
                        onToggleTask: (i) => _toggleTask(0 - 0 + _taskIndex(i)),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          controller: _bodyCtl,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            hintText: 'Write Markdown... - [ ] task lists work',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '${counts.words} words, ${counts.chars} chars - autosaved',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Preview lists one CheckboxListTile per task line in order; the block
  /// index maps directly to the Nth task line in the source.
  int _taskIndex(int blockIndex) => blockIndex;

  Future<void> _menu(String action, Note note) async {
    final repo = ref.read(noteRepositoryProvider);
    switch (action) {
      case 'pin':
        await repo.setPinned(note.id, !note.pinned);
        if (mounted) setState(() {});
      case 'duplicate':
        final id = await repo.duplicateNote(note.id);
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => NoteEditorScreen(noteId: id),
            ),
          );
        }
      case 'move':
        final folderId = await _pickFolder();
        if (folderId != null || _moveConfirmed) {
          await repo.updateNote(note.id, folderId: () => folderId);
        }
      case 'share':
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Share sheet not wired on this build.'),
            ),
          );
        }
      case 'delete':
        await repo.trashNote(note.id);
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Note trashed'),
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => repo.restoreNote(note.id),
              ),
            ),
          );
        }
    }
  }

  bool _moveConfirmed = false;

  Future<String?> _pickFolder() async {
    final folders = await ref.read(noteRepositoryProvider).childFolders(null);
    if (!mounted) return null;
    _moveConfirmed = false;
    return showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Move to folder'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              _moveConfirmed = true;
              Navigator.of(ctx).pop(null);
            },
            child: const Text('(no folder)'),
          ),
          for (final f in folders)
            SimpleDialogOption(
              onPressed: () {
                _moveConfirmed = true;
                Navigator.of(ctx).pop(f.id);
              },
              child: Text(f.name),
            ),
        ],
      ),
    );
  }
}

final _noteProvider = StreamProvider.family<Note?, String>((ref, id) {
  return ref.watch(noteRepositoryProvider).watchNote(id);
});

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.onAction});

  final void Function(String before, [String after]) onAction;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.format_bold),
            tooltip: 'Bold',
            onPressed: () => onAction('**', '**'),
          ),
          IconButton(
            icon: const Icon(Icons.format_italic),
            tooltip: 'Italic',
            onPressed: () => onAction('*', '*'),
          ),
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: 'Code',
            onPressed: () => onAction('`', '`'),
          ),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Link',
            onPressed: () => onAction('[', '](url)'),
          ),
          IconButton(
            icon: const Icon(Icons.format_list_bulleted),
            tooltip: 'List',
            onPressed: () => onAction('- '),
          ),
          IconButton(
            icon: const Icon(Icons.checklist),
            tooltip: 'Task',
            onPressed: () => onAction('- [ ] '),
          ),
          IconButton(
            icon: const Icon(Icons.title),
            tooltip: 'Heading',
            onPressed: () => onAction('## '),
          ),
          IconButton(
            icon: const Icon(Icons.format_quote),
            tooltip: 'Quote',
            onPressed: () => onAction('> '),
          ),
        ],
      ),
    );
  }
}

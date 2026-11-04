// Note editor: autosave (debounced 800 ms), Read/Edit modes, Markdown toolbar,
// a live preview while editing, tappable checklists, word count, attachments,
// pin/duplicate/move/delete with undo.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../../data/repositories/note_repository.dart';
import '../../settings/application/settings_providers.dart';
import '../../sync/application/pending_operations.dart';
import '../application/notes_providers.dart';
import 'markdown_preview.dart' show MarkdownPreview, countWords;

enum _NoteMode { read, edit }

enum _SaveStatus { idle, saving, saved, failed }

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
  Future<void>? _activeSave;
  _NoteMode _mode = _NoteMode.read;
  _SaveStatus _saveStatus = _SaveStatus.idle;
  bool _loaded = false;
  NoteRepository? _repo;
  dynamic _settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Track the open editor so a kill while writing restores it.
    // Notes autosave to the DB, so no draft row is needed.
    Future.microtask(() async {
      try {
        final repo = await ref.read(settingsRepositoryProvider.future);
        _settings = repo;
        await repo.setOpenSheet('note:${widget.noteId}');
        await repo.setLastRoute('note:${widget.noteId}');
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // Best-effort fallback for process teardown. Normal back navigation is
    // flushed and awaited by the PopScope below.
    // Never use ref after unmount: flush via the cached repository.
    final repo = _repo;
    if (_loaded && repo != null) {
      final id = widget.noteId;
      final title = _titleCtl.text;
      final body = _bodyCtl.text;
      unawaited(() async {
        try {
          await repo.updateNote(id, title: title, body: () => body);
        } catch (_) {
          // Nothing actionable after the widget is gone.
        }
      }());
    }
    final settings = _settings;
    if (settings != null) {
      Future.microtask(() async {
        try {
          if (settings.openSheet == 'note:${widget.noteId}') {
            await settings.setOpenSheet(null);
          }
        } catch (_) {}
      });
    }
    _titleCtl.dispose();
    _bodyCtl.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _flush);
  }

  void _setSaveStatus(_SaveStatus status) {
    if (!mounted || _saveStatus == status) return;
    setState(() => _saveStatus = status);
  }

  Future<void> _flush() {
    final repo = _repo;
    if (!_loaded || repo == null) return Future<void>.value();
    // Chain every save so a back gesture always waits for the newest
    // controller text, even while an earlier save is still in flight.
    final save = _saveAfter(_activeSave, repo);
    _activeSave = save;
    return save;
  }

  Future<void> _saveAfter(Future<void>? previous, NoteRepository repo) async {
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // The chained save must still run after an earlier failure.
      }
    }
    if (!mounted) return;
    _setSaveStatus(_SaveStatus.saving);
    try {
      await repo.updateNote(
        widget.noteId,
        title: _titleCtl.text,
        body: () => _bodyCtl.text,
      );
      _setSaveStatus(_SaveStatus.saved);
    } catch (_) {
      _setSaveStatus(_SaveStatus.failed);
    }
  }

  void _toggleMode() {
    if (_mode == _NoteMode.edit) {
      // Switching to Read shows the controller text immediately while the
      // flush persists it in the background.
      unawaited(_flush());
    }
    setState(() {
      _mode = _mode == _NoteMode.read ? _NoteMode.edit : _NoteMode.read;
    });
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Persist before a back gesture leaves the editor.
        await _flush();
        if (context.mounted) Navigator.of(context).pop(result);
      },
      child: noteAsync.when(
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
          final editing = _mode == _NoteMode.edit;
          final title = _titleCtl.text.trim();
          return CallbackShortcuts(
            bindings: {
              SingleActivator(LogicalKeyboardKey.enter, control: true): () {
                if (!mounted) return;
                _flush();
              },
              SingleActivator(LogicalKeyboardKey.escape): () {
                if (!mounted) return;
                Navigator.of(context).maybePop();
              },
            },
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Note'),
                actions: [
                  IconButton(
                    icon: Icon(
                      editing ? Icons.menu_book_outlined : Icons.edit_outlined,
                    ),
                    tooltip: editing ? 'Read' : 'Edit',
                    onPressed: _toggleMode,
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) => _menu(v, note),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'pin', child: Text('Pin / unpin')),
                      PopupMenuItem(
                        value: 'duplicate',
                        child: Text('Duplicate'),
                      ),
                      PopupMenuItem(
                        value: 'move',
                        child: Text('Move to folder'),
                      ),
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
                    child: editing
                        ? TextField(
                            key: const Key('note-title'),
                            controller: _titleCtl,
                            decoration: const InputDecoration(
                              hintText: 'Title',
                              border: InputBorder.none,
                            ),
                            style: Theme.of(context).textTheme.headlineSmall,
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              title.isEmpty ? 'Untitled' : title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                  ),
                  if (editing) _Toolbar(onAction: _wrap),
                  Expanded(
                    child: editing
                        ? _EditorSplit(controller: _bodyCtl)
                        : MarkdownPreview(
                            body: _bodyCtl.text,
                            onToggleTask: _toggleTask,
                          ),
                  ),
                  _StatusLine(controller: _bodyCtl, status: _saveStatus),
                  _LinksSection(noteId: widget.noteId),
                ],
              ), // Column
            ), // Scaffold
          ); // CallbackShortcuts
        },
      ),
    );
  }

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
        final pending = ref.read(pendingOperationsProvider);
        final opId = await pending.scheduleNoteTrash(note.id);
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Note trashed'),
              duration: const Duration(seconds: 6),
              persist: false,
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => pending.cancel(opId),
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

/// Body editor plus a live preview. Wide layouts split side by side; phone
/// layouts stack them vertically so the keyboard never hides the preview.
class _EditorSplit extends StatelessWidget {
  const _EditorSplit({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final editor = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            key: const Key('note-body'),
            controller: controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              hintText: 'Write Markdown... - [ ] task lists work',
              border: InputBorder.none,
            ),
          ),
        );
        final preview = _LivePreview(controller: controller);
        if (constraints.maxWidth >= 720) {
          return Row(
            children: [
              Expanded(child: editor),
              const VerticalDivider(width: 1),
              Expanded(child: preview),
            ],
          );
        }
        return Column(
          children: [
            Expanded(flex: 3, child: editor),
            const Divider(height: 1),
            Expanded(flex: 2, child: preview),
          ],
        );
      },
    );
  }
}

/// Rebuilds only the preview subtree as the body changes.
class _LivePreview extends StatelessWidget {
  const _LivePreview({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        // Editing preview is display-only so taps cannot steal focus.
        return IgnorePointer(
          child: RepaintBoundary(
            child: MarkdownPreview(
              key: const Key('note-live-preview'),
              body: value.text,
            ),
          ),
        );
      },
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.controller, required this.status});

  final TextEditingController controller;
  final _SaveStatus status;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final counts = countWords(value.text);
        final label = switch (status) {
          _SaveStatus.idle => 'Autosave on',
          _SaveStatus.saving => 'Saving...',
          _SaveStatus.saved => 'Saved',
          _SaveStatus.failed => 'Save failed',
        };
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${counts.words} words, ${counts.chars} chars - $label',
            key: const Key('note-save-status'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: status == _SaveStatus.failed
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
        );
      },
    );
  }
}

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

/// Outgoing [[links]] and incoming backlinks. Tapping a missing title
/// creates the note; tapping an existing one opens it.
class _LinksSection extends ConsumerWidget {
  const _LinksSection({required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<(_Links, void)>(
      future: _load(ref),
      builder: (ctx, snap) {
        final links = snap.data?.$1;
        if (links == null ||
            (links.outgoing.isEmpty &&
                links.outgoingMissing.isEmpty &&
                links.incoming.isEmpty)) {
          return const SizedBox.shrink();
        }
        return Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Icon(Icons.link, size: 16),
                const SizedBox(width: 6),
                for (final n in links.outgoing)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ActionChip(
                      label: Text(n.title),
                      onPressed: () => _open(context, n.id),
                    ),
                  ),
                for (final title in links.outgoingMissing)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ActionChip(
                      label: Text('$title +'),
                      tooltip: 'Create note "$title"',
                      onPressed: () => _create(context, ref, title),
                    ),
                  ),
                for (final n in links.incoming)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InputChip(
                      label: Text(n.title),
                      avatar: const Icon(Icons.reply, size: 16),
                      tooltip: 'Linked from "${n.title}"',
                      onPressed: () => _open(context, n.id),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<(_Links, void)> _load(WidgetRef ref) async {
    final repo = ref.read(noteRepositoryProvider);
    final note = await repo.getNote(noteId);
    final titles = NoteRepository.extractLinkedTitles(note?.body);
    final outgoing = await repo.forwardLinks(noteId);
    final have = outgoing.map((n) => n.title).toSet();
    final missing = titles.where((t) => !have.contains(t)).toList();
    final incoming = await repo.backlinks(noteId);
    return (_Links(outgoing, missing, incoming), null);
  }

  void _open(BuildContext context, String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(noteId: id)),
    );
  }

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    String title,
  ) async {
    final id = await ref.read(noteRepositoryProvider).createNote(title: title);
    if (context.mounted) _open(context, id);
  }
}

class _Links {
  const _Links(this.outgoing, this.outgoingMissing, this.incoming);
  final List<Note> outgoing;
  final List<String> outgoingMissing;
  final List<Note> incoming;
}

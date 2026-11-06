part of '../note_editor_screen.dart';

// Editor screen state: open-sheet route bookkeeping, debounced autosave,
// Read/Edit body rendering and controller-side Markdown actions.

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen>
    with _EditorMenuOps {
  final _titleCtl = TextEditingController();
  final _bodyCtl = MarkdownEditingController();
  Timer? _saveTimer;
  Future<void>? _activeSave;
  _NoteMode _mode = _NoteMode.read;
  _SaveStatus _saveStatus = _SaveStatus.idle;
  bool _allowPop = false;
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
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _allowPop) return;
        // Persist before a back gesture leaves the editor.
        await _flush();
        if (!mounted) return;
        setState(() => _allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(result);
        });
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
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: TextField(
                              key: const Key('note-body'),
                              controller: _bodyCtl,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              decoration: const InputDecoration(
                                hintText:
                                    'Write Markdown... - [ ] task lists work',
                                border: InputBorder.none,
                              ),
                            ),
                          )
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
}

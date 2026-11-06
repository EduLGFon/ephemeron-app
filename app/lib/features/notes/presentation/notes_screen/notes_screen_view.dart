part of '../notes_screen.dart';

// Notes screen view and state.

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key, this.linkedEventId});

  /// When set, the screen creates/lists notes linked to an event.
  final String? linkedEventId;

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  String? _folderId;
  String _query = '';
  bool _folderRestored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_folderRestored) {
      _folderRestored = true;
      Future.microtask(() async {
        try {
          final repo = await ref.read(settingsRepositoryProvider.future);
          final saved = repo.selectedNotesFolderId;
          if (saved != _folderId && mounted) {
            setState(() => _folderId = saved);
          }
          ref.read(selectedFolderProvider.notifier).select(saved);
        } catch (_) {}
      });
    }
  }

  Future<void> _navigateFolder(String? id) async {
    setState(() => _folderId = id);
    ref.read(selectedFolderProvider.notifier).select(id);
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.setSelectedNotesFolderId(id);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(foldersProvider(_folderId));
    final notesAsync = ref.watch(folderNotesProvider(_folderId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _search(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Trash',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _TrashScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'Export ZIP',
            onPressed: _exportZip,
          ),
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: 'Import .md / .txt',
            onPressed: _importFiles,
          ),
        ],
      ),
      body: Column(
        children: [
          _Breadcrumbs(
            folderId: _folderId,
            onNavigate: (id) => _navigateFolder(id),
          ),
          Expanded(
            child: foldersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(
                message: 'Could not load folders.',
                onRetry: () => ref.invalidate(foldersProvider(_folderId)),
              ),
              data: (folders) => notesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorState(
                  message: 'Could not load notes.',
                  onRetry: () => ref.invalidate(folderNotesProvider(_folderId)),
                ),
                data: (notes) {
                  if (folders.isEmpty && notes.isEmpty) {
                    return EmptyState(
                      icon: Icons.note_outlined,
                      title: 'No notes here',
                      actionLabel: 'New note',
                      onAction: () => _newNote(),
                    );
                  }
                  final items = <Widget>[];
                  for (final f in folders) {
                    items.add(
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(f.name),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v != 'delete') return;
                            final pending = ref.read(pendingOperationsProvider);
                            final opId = await pending.scheduleFolderDelete(
                              f.id,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Deleted folder "${f.name}"'),
                                duration: const Duration(seconds: 6),
                                persist: false,
                                action: SnackBarAction(
                                  label: 'Undo',
                                  onPressed: () => pending.cancel(opId),
                                ),
                              ),
                            );
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete folder'),
                            ),
                          ],
                        ),
                        onTap: () => _navigateFolder(f.id),
                      ),
                    );
                  }
                  for (final n in notes) {
                    items.add(
                      Dismissible(
                        key: ValueKey(n.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (_) async {
                          final pending = ref.read(pendingOperationsProvider);
                          final opId = await pending.scheduleNoteTrash(n.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Trashed "${n.title}"'),
                                duration: const Duration(seconds: 6),
                                persist: false,
                                action: SnackBarAction(
                                  label: 'Undo',
                                  onPressed: () => pending.cancel(opId),
                                ),
                              ),
                            );
                          }
                          return false;
                        },
                        child: ListTile(
                          leading: n.pinned
                              ? const Icon(Icons.push_pin, size: 18)
                              : null,
                          title: Text(n.title.isEmpty ? '(untitled)' : n.title),
                          subtitle: _subtitle(n),
                          onTap: () => _openNote(n),
                        ),
                      ),
                    );
                  }
                  return RepaintBoundary(
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) => items[i],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'new-folder',
            onPressed: _newFolder,
            child: const Icon(Icons.create_new_folder_outlined),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'new-note',
            onPressed: _newFromTemplate,
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget? _subtitle(Note n) {
    final body = (n.body ?? '').trim();
    if (body.isEmpty && n.linkedEventId == null) return null;
    final first = body
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final text = n.linkedEventId != null ? '[event] $first' : first;
    if (text.isEmpty) return null;
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  Future<void> _newNote({String template = ''}) async {
    final repo = ref.read(noteRepositoryProvider);
    final id = await repo.createNote(
      title: template.isEmpty ? '' : 'Meeting notes',
      body: template.isEmpty ? null : template,
      folderId: _folderId,
      linkedEventId: widget.linkedEventId,
    );
    if (mounted) _openById(id);
  }

  Future<void> _newFromTemplate() async {
    final choice = await showAppSheet<String>(
      context,
      builder: (ctx) => EscapeToClose(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Blank'),
                onTap: () => Navigator.of(ctx).pop('blank'),
              ),
              ListTile(
                title: const Text('Meeting notes'),
                onTap: () => Navigator.of(ctx).pop('meeting'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == 'meeting') {
      await _newNote(
        template: '## Attendees\n\n- \n\n## Agenda\n\n- \n\n## Notes\n\n',
      );
    } else if (choice == 'blank') {
      await _newNote();
    }
  }

  void _openNote(Note n) => _openById(n.id);

  void _openById(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(noteId: id)),
    );
  }

  Future<void> _importFiles() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'txt'],
      );
      if (files.isEmpty) return;
      final repo = ref.read(noteRepositoryProvider);
      var count = 0;
      for (final f in files) {
        if (f.path != null) {
          await repo.importMarkdownFile(f.path!, folderId: _folderId);
          count++;
        } else {
          final bytes = await f.readAsBytes();
          final id = await repo.createNote(
            title: f.name.contains('.')
                ? f.name.substring(0, f.name.lastIndexOf('.'))
                : f.name,
            body: utf8.decode(bytes, allowMalformed: true),
            folderId: _folderId,
          );
          if (id.isNotEmpty) count++;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Imported $count file(s)')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<void> _exportZip() async {
    try {
      final notes = ref.read(folderNotesProvider(_folderId)).value ?? const [];
      final archive = Archive();
      for (final n in notes) {
        final name = (n.title.isEmpty ? 'untitled' : n.title).replaceAll(
          RegExp(r'[\\\\/:*?"<>|]'),
          '_',
        );
        final body = n.body ?? '';
        archive.addFile(ArchiveFile('$name.md', body.length, body.codeUnits));
      }
      final data = ZipEncoder().encode(archive);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/notes-export.zip');
      await file.writeAsBytes(data);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Exported to ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _newFolder() async {
    final name = await showPromptDialog(
      context,
      title: 'New folder',
      hint: 'Name',
    );
    if (name != null && name.isNotEmpty) {
      await ref
          .read(noteRepositoryProvider)
          .createFolder(name, parentId: _folderId);
    }
  }

  Future<void> _search(BuildContext context) async {
    final query = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctl = TextEditingController(text: _query);
        return AlertDialog(
          title: const Text('Search notes'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctl.text),
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
    if (query == null || query.trim().isEmpty) return;
    if (!mounted) return;
    setState(() => _query = query);
    final hits = await ref.read(noteRepositoryProvider).searchNotes(query);
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _SearchResults(query: query, hits: hits, onOpen: _openById),
      ),
    );
  }
}

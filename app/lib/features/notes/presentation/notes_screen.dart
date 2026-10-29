// Notes screen: nested folders with breadcrumbs, note list with counts,
// FTS search with snippets, trash, new note / new folder.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../application/notes_providers.dart';
import 'note_editor_screen.dart';

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
              MaterialPageRoute<void>(
                  builder: (_) => const _TrashScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _Breadcrumbs(
            folderId: _folderId,
            onNavigate: (id) => setState(() => _folderId = id),
          ),
          Expanded(
            child: foldersAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(
                  message: 'Could not load folders.',
                  onRetry: () =>
                      ref.invalidate(foldersProvider(_folderId))),
              data: (folders) => notesAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator()),
                error: (e, _) => _ErrorState(
                    message: 'Could not load notes.',
                    onRetry: () =>
                        ref.invalidate(folderNotesProvider(_folderId))),
                data: (notes) {
                  if (folders.isEmpty && notes.isEmpty) {
                    return _EmptyState(onAdd: () => _newNote());
                  }
                  return ListView(
                    children: [
                      for (final f in folders)
                        ListTile(
                          leading:
                              const Icon(Icons.folder_outlined),
                          title: Text(f.name),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'delete') {
                                ref
                                    .read(noteRepositoryProvider)
                                    .deleteFolder(f.id);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete folder')),
                            ],
                          ),
                          onTap: () =>
                              setState(() => _folderId = f.id),
                        ),
                      for (final n in notes)
                        Dismissible(
                          key: ValueKey(n.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            child: const Icon(Icons.delete,
                                color: Colors.white),
                          ),
                          confirmDismiss: (_) async {
                            await ref
                                .read(noteRepositoryProvider)
                                .trashNote(n.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Trashed "${n.title}"'),
                                  duration:
                                      const Duration(seconds: 6),
                                  action: SnackBarAction(
                                    label: 'Undo',
                                    onPressed: () => ref
                                        .read(noteRepositoryProvider)
                                        .restoreNote(n.id),
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
                            title: Text(n.title.isEmpty
                                ? '(untitled)'
                                : n.title),
                            subtitle: _subtitle(n),
                            onTap: () => _openNote(n),
                          ),
                        ),
                    ],
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
            onPressed: _newNote,
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget? _subtitle(Note n) {
    final body = (n.body ?? '').trim();
    if (body.isEmpty && n.linkedEventId == null) return null;
    final first =
        body.split('\n').firstWhere((l) => l.trim().isNotEmpty,
            orElse: () => '');
    final text =
        n.linkedEventId != null ? '[event] $first' : first;
    if (text.isEmpty) return null;
    return Text(text,
        maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  Future<void> _newNote() async {
    final repo = ref.read(noteRepositoryProvider);
    final id = await repo.createNote(
      title: '',
      folderId: _folderId,
      linkedEventId: widget.linkedEventId,
    );
    if (mounted) _openById(id);
  }

  void _openNote(Note n) => _openById(n.id);

  void _openById(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) => NoteEditorScreen(noteId: id)),
    );
  }

  Future<void> _newFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration:
                const InputDecoration(hintText: 'Name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Create')),
        ],
      ),
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
              onSubmitted: (v) => Navigator.of(ctx).pop(v)),
          actions: [
            FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(ctl.text),
                child: const Text('Search')),
          ],
        );
      },
    );
    if (query == null || query.trim().isEmpty || !mounted) return;
    setState(() => _query = query);
    final hits =
        await ref.read(noteRepositoryProvider).searchNotes(query);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) => _SearchResults(
              query: query,
              hits: hits,
              onOpen: _openById)),
    );
  }
}

class _Breadcrumbs extends ConsumerWidget {
  const _Breadcrumbs({required this.folderId, required this.onNavigate});

  final String? folderId;
  final ValueChanged<String?> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (folderId == null) {
      return const ListTile(
          title: Text('All folders'), enabled: false);
    }
    return FutureBuilder(
      future: ref.read(noteRepositoryProvider).breadcrumbs(folderId!),
      builder: (ctx, snap) {
        final crumbs = snap.data ?? const <Folder>[];
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              TextButton(
                  onPressed: () => onNavigate(null),
                  child: const Text('All')),
              for (final f in crumbs) ...[
                const Text('/'),
                TextButton(
                    onPressed: () => onNavigate(f.id),
                    child: Text(f.name)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults(
      {required this.query, required this.hits, required this.onOpen});

  final String query;
  final List<dynamic> hits;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Results for "$query"')),
      body: hits.isEmpty
          ? const Center(child: Text('No matches'))
          : ListView(
              children: [
                for (final h in hits)
                  ListTile(
                    title: Text((h.note as Note).title),
                    subtitle: Text((h.snippet as String)
                        .replaceAll('<b>', '')
                        .replaceAll('</b>', '')),
                    onTap: () => onOpen((h.note as Note).id),
                  ),
              ],
            ),
    );
  }
}

class _TrashScreen extends ConsumerWidget {
  const _TrashScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashAsync = ref.watch(noteTrashProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Trash')),
      body: trashAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Could not load.')),
        data: (notes) {
          if (notes.isEmpty) {
            return const Center(child: Text('Trash is empty'));
          }
          return ListView(
            children: [
              for (final n in notes)
                ListTile(
                  title: Text(n.title),
                  trailing: IconButton(
                    icon: const Icon(Icons.restore),
                    onPressed: () => ref
                        .read(noteRepositoryProvider)
                        .restoreNote(n.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.note_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('No notes here'),
          const SizedBox(height: 8),
          FilledButton(onPressed: onAdd, child: const Text('New note')),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

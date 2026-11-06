part of '../notes_screen.dart';

// Renders the folder/note list body for the notes screen.

class _NotesListBody extends ConsumerWidget {
  const _NotesListBody({
    required this.folders,
    required this.notes,
    required this.onFolderTap,
    required this.onNoteTap,
    required this.onNewNote,
  });

  final List<Folder> folders;
  final List<Note> notes;
  final ValueChanged<String> onFolderTap;
  final ValueChanged<Note> onNoteTap;
  final VoidCallback onNewNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (folders.isEmpty && notes.isEmpty) {
      return EmptyState(
        icon: Icons.note_outlined,
        title: 'No notes here',
        actionLabel: 'New note',
        onAction: onNewNote,
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
              final opId = await pending.scheduleFolderDelete(f.id);
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
              PopupMenuItem(value: 'delete', child: Text('Delete folder')),
            ],
          ),
          onTap: () => onFolderTap(f.id),
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
            leading: n.pinned ? const Icon(Icons.push_pin, size: 18) : null,
            title: Text(n.title.isEmpty ? '(untitled)' : n.title),
            subtitle: _noteSubtitle(n),
            onTap: () => onNoteTap(n),
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
  }
}

Widget? _noteSubtitle(Note n) {
  final body = (n.body ?? '').trim();
  if (body.isEmpty && n.linkedEventId == null) return null;
  final first = body
      .split('\n')
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  final text = n.linkedEventId != null ? '[event] $first' : first;
  if (text.isEmpty) return null;
  return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
}

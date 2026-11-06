part of '../note_editor_screen.dart';

// App bar menu actions (pin, duplicate, move, share stub, delete with undo)
// and the folder picker dialog, mixed into the editor state so the methods
// keep plain `mounted`, `setState` and `ref` access.

mixin _EditorMenuOps on ConsumerState<NoteEditorScreen> {
  bool _moveConfirmed = false;

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

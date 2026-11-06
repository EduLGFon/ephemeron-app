part of '../note_editor_screen.dart';

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

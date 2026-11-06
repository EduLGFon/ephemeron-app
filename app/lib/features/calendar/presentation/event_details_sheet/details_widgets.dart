part of '../event_details_sheet.dart';

/// Read-only source row shown under an event or task title.
class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.kind,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String kind;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(kind),
      dense: true,
      trailing: onTap == null ? null : const Icon(Icons.swap_horiz),
      onTap: onTap,
    );
  }
}

class _Attendees extends ConsumerWidget {
  const _Attendees({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Same self-resolution as the timeline/agenda styling: flagged row,
    // then account-email match, so pre-flag rows keep their response chips.
    final accounts = ref.watch(googleAccountsProvider);
    final active = ref.watch(googleAccountProvider);
    final emails = active == null ? accounts : [active, ...accounts];
    return FutureBuilder<List<EventAttendee>>(
      future: ref.read(eventRepositoryProvider).attendeesOf(eventId),
      builder: (ctx, snap) {
        final atts = snap.data ?? const [];
        if (atts.isEmpty) return const SizedBox.shrink();
        final self = EventRepository.resolveSelf(atts, emails);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final a in atts)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(a.email),
                trailing: Text(a.rsvp ?? ''),
              ),
            if (self != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('My response:'),
                    for (final (value, label) in const [
                      ('accepted', 'Yes'),
                      ('tentative', 'Maybe'),
                      ('declined', 'No'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: (self.rsvp ?? '') == value,
                        onSelected: (_) => _respond(ctx, ref, self, value),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref,
    EventAttendee self,
    String rsvp,
  ) async {
    await ref.read(eventRepositoryProvider).setRsvp(self.id, rsvp);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('RSVP: $rsvp')));
    }
  }
}

class _LinkedNotes extends ConsumerWidget {
  const _LinkedNotes({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes =
        ref.watch(eventNotesProvider(eventId)).value ?? const <Note>[];
    if (notes.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final n in notes)
          ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: Text(n.title.isEmpty ? '(untitled)' : n.title),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NoteEditorScreen(noteId: n.id),
                ),
              );
            },
          ),
      ],
    );
  }
}

String _when(BuildContext context, Event e) {
  if (e.isAllDay) {
    if (e.startDate == null) return '';
    try {
      return DeviceDateFormat.yMMMd(
        context,
      ).format(DateTime.parse(e.startDate!));
    } catch (_) {
      return e.startDate!;
    }
  }
  final s = e.startUtc == null
      ? '?'
      : DeviceDateFormat.yMMMd(context).add_Hm().format(
          DateTime.fromMillisecondsSinceEpoch(
            e.startUtc!,
            isUtc: true,
          ).toLocal(),
        );
  final en = e.endUtc == null
      ? ''
      : ' - ${DeviceDateFormat.hm(context).format(DateTime.fromMillisecondsSinceEpoch(e.endUtc!, isUtc: true).toLocal())}';
  return '$s$en';
}

// Event details sheet: view, edit, delete with scope, duplicate.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/drift/app_database.dart';
import '../../../data/repositories/event_repository.dart';
import '../../notes/application/notes_providers.dart';
import '../../notes/presentation/note_editor_screen.dart';
import '../application/calendar_providers.dart';
import 'event_editor_sheet.dart';
import 'scope_sheet.dart';

Future<void> showEventDetails(BuildContext context, String eventId) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => _Details(eventId: eventId),
  );
}

class _Details extends ConsumerWidget {
  const _Details({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Event?>(
      future:
          (ref.read(eventRepositoryProvider).dbSelect()
                ..where((e) => e.id.equals(eventId)))
              .getSingleOrNull(),
      builder: (ctx, snap) {
        final e = snap.data;
        if (e == null) {
          return const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Event not found'),
            ),
          );
        }
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              ListTile(
                title: Text(
                  e.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                subtitle: Text(_when(e)),
              ),
              if (e.location != null && e.location!.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(e.location!),
                ),
              if (e.meetUrl != null && e.meetUrl!.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: Text(e.meetUrl!),
                  subtitle: const Text('Google Meet'),
                ),
              if (e.notes != null && e.notes!.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.notes_outlined),
                  title: Text(e.notes!),
                ),
              _Attendees(eventId: e.id),
              _LinkedNotes(eventId: e.id),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          showEventEditor(context, event: e);
                        },
                        child: const Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _delete(context, ref, e),
                        child: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final noteRepo = ref.read(noteRepositoryProvider);
                    final id = await noteRepo.createNote(
                      title: 'Notes for ${e.title}',
                      linkedEventId: e.id,
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => NoteEditorScreen(noteId: id),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Add note'),
                ),
              ),
            ],
          ),
        ),
      );
      },
    );
  }
}

class _Attendees extends ConsumerWidget {
  const _Attendees({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<EventAttendee>>(
      future: ref.read(eventRepositoryProvider).attendeesOf(eventId),
      builder: (ctx, snap) {
        final atts = snap.data ?? const [];
        if (atts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final a in atts)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(a.email),
                trailing: Text(a.rsvp ?? ''),
              ),
          ],
        );
      },
    );
  }
}

class _LinkedNotes extends ConsumerWidget {
  const _LinkedNotes({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<Note>>(
      future: ref.read(noteRepositoryProvider).notesForEvent(eventId),
      builder: (ctx, snap) {
        final notes = snap.data ?? const <Note>[];
        if (notes.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            for (final n in notes)
              ListTile(
                leading: const Icon(Icons.sticky_note_2_outlined),
                title: Text(n.title.isEmpty ? '(untitled)' : n.title),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NoteEditorScreen(noteId: n.id),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

String _when(Event e) {
  if (e.isAllDay) return e.startDate ?? '';
  final s = e.startUtc == null
      ? '?'
      : DateFormat.yMMMd().add_Hm().format(
          DateTime.fromMillisecondsSinceEpoch(e.startUtc!, isUtc: true).toLocal(),
        );
  final en = e.endUtc == null
      ? ''
      : ' - ${DateFormat.Hm().format(DateTime.fromMillisecondsSinceEpoch(e.endUtc!, isUtc: true).toLocal())}';
  return '$s$en';
}

Future<void> _delete(BuildContext context, WidgetRef ref, Event e) async {
  final repo = ref.read(eventRepositoryProvider);
  final recurring =
      e.rrule != null && e.rrule!.isNotEmpty && e.recurringMasterId == null;
  EditScope scope = EditScope.all;
  DateTime orig = DateTime.now().toUtc();
  if (recurring) {
    if (!context.mounted) return;
    final s = await showScopeSheet(context);
    if (s == null) return;
    scope = s;
    orig = DateTime.fromMillisecondsSinceEpoch(e.startUtc ?? 0, isUtc: true);
    if (!context.mounted) return;
    if (scope == EditScope.single || scope == EditScope.following) {
      await repo.deleteOccurrence(e.id, orig, scope: scope);
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event deleted'),
            duration: Duration(seconds: 6),
          ),
        );
      }
      return;
    }
  }
  if (!context.mounted) return;
  final confirm =
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete event?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
  if (!confirm || !context.mounted) return;
  await repo.deleteEvent(e.id);
  if (context.mounted) {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Event deleted'),
        duration: Duration(seconds: 6),
      ),
    );
  }
}

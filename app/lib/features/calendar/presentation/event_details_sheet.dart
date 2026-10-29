// Event details sheet: view, edit, delete with scope, duplicate.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../../data/repositories/event_repository.dart';
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
              if (e.notes != null && e.notes!.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.notes_outlined),
                  title: Text(e.notes!),
                ),
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
            ],
          ),
        );
      },
    );
  }

  String _when(Event e) {
    if (e.isAllDay) return e.startDate ?? '';
    final s = e.startUtc == null
        ? '?'
        : DateTime.fromMillisecondsSinceEpoch(
            e.startUtc!,
            isUtc: true,
          ).toLocal().toString().substring(0, 16);
    final en = e.endUtc == null
        ? ''
        : ' - ${DateTime.fromMillisecondsSinceEpoch(e.endUtc!, isUtc: true).toLocal().toString().substring(11, 16)}';
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
}

// Event details sheet: view, edit, delete with scope, duplicate.
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/system_launcher.dart';
import '../../../core/ui/app_sheet.dart';
import '../../../core/ui/escape_to_close.dart';
import '../../../data/drift/app_database.dart';
import '../../../core/db/db_provider.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../domain/sources/microsoft_source.dart';
import '../../../domain/sources/source_label.dart';
import '../../auth/application/auth_providers.dart';
import '../../notes/application/notes_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../sync/application/pending_operations.dart';
import '../../tasks/application/tasks_providers.dart';
import '../../notes/presentation/note_editor_screen.dart';
import '../../tasks/presentation/task_editor_sheet.dart';
import '../../tasks/presentation/task_source_picker.dart';
import '../application/calendar_providers.dart';
import 'calendar_source_picker.dart';
import 'event_editor_sheet.dart';
import 'scope_sheet.dart';

Future<void> showEventDetails(BuildContext context, String eventId) async {
  // Track the open modal so a kill while viewing restores it.
  // Normal close clears the marker below; process kill skips it.
  try {
    final container = ProviderScope.containerOf(context);
    final repo = await container.read(settingsRepositoryProvider.future);
    await repo.setOpenSheet('event_details:$eventId');
  } catch (_) {}
  if (!context.mounted) return;
  try {
    await showAppSheet<void>(
      context,
      builder: (_) => EscapeToClose(child: _Details(eventId: eventId)),
    );
  } finally {
    try {
      if (context.mounted) {
        final container = ProviderScope.containerOf(context);
        final repo = await container.read(settingsRepositoryProvider.future);
        if (repo.openSheet == 'event_details:$eventId') {
          await repo.setOpenSheet(null);
        }
      }
    } catch (_) {}
  }
}

/// Event or task detail row plus the resolved source label.
class _LoadedDetails {
  const _LoadedDetails({
    this.event,
    this.task,
    this.source,
    this.isMicrosoft = false,
  });

  final Event? event;
  final Task? task;
  final String? source;
  final bool isMicrosoft;
}

class _Details extends ConsumerStatefulWidget {
  const _Details({required this.eventId});

  final String eventId;

  @override
  ConsumerState<_Details> createState() => _DetailsState();
}

class _DetailsState extends ConsumerState<_Details> {
  late Future<_LoadedDetails?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load(ref, widget.eventId);
  }

  void _reload() {
    setState(() => _future = _load(ref, widget.eventId));
  }

  Future<_LoadedDetails?> _load(WidgetRef ref, String id) async {
    final db = ref.read(appDatabaseProvider);
    final event =
        await (ref.read(eventRepositoryProvider).dbSelect()
              ..where((e) => e.id.equals(id)))
            .getSingleOrNull();
    if (event != null) {
      final calendar = await (db.select(
        db.calendars,
      )..where((c) => c.id.equals(event.calendarId))).getSingleOrNull();
      final isMs = isMicrosoftEvent(
        eventMicrosoftAccount: event.microsoftAccount,
        calendarSource: calendar?.source,
        calendarMicrosoftAccount: calendar?.microsoftAccount,
      );
      return _LoadedDetails(
        event: event,
        isMicrosoft: isMs,
        source: sourceLabel(
          name: calendar?.name,
          account: accountForSource(
            googleAccount: event.googleAccount,
            microsoftAccount: event.microsoftAccount,
          ),
          fallbackAccount: accountForSource(
            googleAccount: calendar?.googleAccount,
            microsoftAccount: calendar?.microsoftAccount,
          ),
          isLocal:
              calendar?.source != 'google' && calendar?.source != 'microsoft',
        ),
      );
    }
    final task = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (task == null) return null;
    final listId = task.listId;
    final list = listId == null
        ? null
        : await (db.select(
            db.taskLists,
          )..where((l) => l.id.equals(listId))).getSingleOrNull();
    final isMs = isMicrosoftTask(
      taskMicrosoftAccount: task.microsoftAccount,
      listMicrosoftAccount: list?.microsoftAccount,
    );
    return _LoadedDetails(
      task: task,
      isMicrosoft: isMs,
      source: sourceLabel(
        name: list?.name,
        account: accountForSource(
          googleAccount: task.googleAccount,
          microsoftAccount: task.microsoftAccount,
        ),
        fallbackAccount: accountForSource(
          googleAccount: list?.googleAccount,
          microsoftAccount: list?.microsoftAccount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LoadedDetails?>(
      future: _future,
      builder: (ctx, snap) {
        final data = snap.data;
        final e = data?.event;
        if (e != null) {
          final source = data?.source;
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
                    subtitle: Text(_when(context, e)),
                  ),
                  _SourceTile(
                    icon: Icons.calendar_today_outlined,
                    kind: 'Calendar',
                    label: source ?? 'Unknown calendar',
                    onTap: data?.isMicrosoft == true
                        ? null
                        : () async {
                            final moved = await pickAndMoveEvent(
                              context,
                              ref,
                              eventId: e.id,
                              currentCalendarId: e.calendarId,
                            );
                            if (moved && context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
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
                      trailing: IconButton(
                        icon: const Icon(Icons.open_in_new),
                        tooltip: 'Join meeting',
                        onPressed: () async {
                          final ok = await SystemLauncher.openUrl(e.meetUrl!);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? 'Opening meeting'
                                    : 'Join not supported here - link copied',
                              ),
                            ),
                          );
                          if (!ok) {
                            await Clipboard.setData(
                              ClipboardData(text: e.meetUrl!),
                            );
                          }
                        },
                      ),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: e.meetUrl!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Meet link copied')),
                        );
                      },
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
                            onPressed: () async {
                              await showEventEditor(context, event: e);
                              if (mounted) _reload();
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
                        if (!context.mounted) return;
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => NoteEditorScreen(noteId: id),
                          ),
                        );
                        if (mounted) _reload();
                      },
                      icon: const Icon(Icons.note_add_outlined),
                      label: const Text('Add note'),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else if (data?.task case final t?) {
          final source = data?.source;
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    title: Text(
                      t.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    subtitle: Text(
                      t.dueDate == null
                          ? 'No due date'
                          : 'Due ${DeviceDateFormat.dateIso(context, t.dueDate!)}${t.dueTime == null ? '' : ' ${t.dueTime! ~/ 60}:${(t.dueTime! % 60).toString().padLeft(2, '0')}'}',
                    ),
                  ),
                  _SourceTile(
                    icon: Icons.list_alt_outlined,
                    kind: 'List',
                    label: source ?? 'No list',
                    onTap: data?.isMicrosoft == true
                        ? null
                        : () async {
                            final moved = await pickAndMoveTask(
                              context,
                              ref,
                              taskId: t.id,
                              currentListId: t.listId,
                            );
                            if (moved && context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                  ),
                  if (t.notes != null && t.notes!.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.notes_outlined),
                      title: Text(t.notes!),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: data?.isMicrosoft == true
                                ? null
                                : () {
                                    Navigator.of(context).pop();
                                    showTaskEditor(context, task: t);
                                  },
                            child: const Text('Edit'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: data?.isMicrosoft == true
                                ? null
                                : () async {
                                    final pending = ref.read(
                                      pendingOperationsProvider,
                                    );
                                    final opId = await pending
                                        .scheduleTaskDelete(t.id);
                                    try {
                                      ref
                                          .read(
                                            occurrenceDirtyProvider.notifier,
                                          )
                                          .markDirty();
                                    } catch (_) {}
                                    if (!context.mounted) return;
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );
                                    Navigator.of(context).pop();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text('Deleted "${t.title}"'),
                                        duration: const Duration(seconds: 6),
                                        persist: false,
                                        action: SnackBarAction(
                                          label: 'Undo',
                                          onPressed: () => pending.cancel(opId),
                                        ),
                                      ),
                                    );
                                  },
                            child: const Text('Delete'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: FilledButton.icon(
                      onPressed:
                          (t.completedAt == null && data?.isMicrosoft != true)
                          ? () async {
                              await ref
                                  .read(taskRepositoryProvider)
                                  .completeTask(t.id);
                              if (context.mounted) Navigator.of(context).pop();
                            }
                          : null,
                      icon: const Icon(Icons.check),
                      label: Text(
                        t.completedAt == null ? 'Mark as done' : 'Completed',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          return const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Event not found'),
            ),
          );
        }
      },
    );
  }
}

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

Future<void> _delete(BuildContext context, WidgetRef ref, Event e) async {
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
      final pending = ref.read(pendingOperationsProvider);
      final opId = await pending.scheduleEventDeleteOccurrence(
        e.id,
        orig,
        scope: scope,
      );
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Event deleted'),
            duration: const Duration(seconds: 6),
            persist: false,
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => pending.cancel(opId),
            ),
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
  final pending = ref.read(pendingOperationsProvider);
  final opId = await pending.scheduleEventDelete(e.id);
  if (context.mounted) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Event deleted'),
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

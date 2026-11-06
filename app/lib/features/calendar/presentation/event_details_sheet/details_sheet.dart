part of '../event_details_sheet.dart';

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
          return _EventDetailsBody(
            event: e,
            source: data?.source,
            isMicrosoft: data?.isMicrosoft == true,
            onReload: _reload,
          );
        } else if (data?.task case final t?) {
          return _TaskDetailsBody(
            task: t,
            source: data?.source,
            isMicrosoft: data?.isMicrosoft == true,
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

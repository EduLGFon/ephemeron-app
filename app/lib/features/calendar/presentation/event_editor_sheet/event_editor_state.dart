// Event editor widget and state shell: fields and lifecycle overrides.
// Draft/autosave helpers live in event_editor_draft.dart, the form build
// in event_editor_view.dart, and save/pickers in event_editor_save.dart.
part of '../event_editor_sheet.dart';

class _EventEditor extends ConsumerStatefulWidget {
  const _EventEditor({
    this.event,
    this.initialDay,
    this.initialHour,
    this.restoredDraft,
  });

  final Event? event;
  final DateTime? initialDay;
  final int? initialHour;
  final Map<String, dynamic>? restoredDraft;

  @override
  ConsumerState<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends ConsumerState<_EventEditor> {
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _notes;
  late final TextEditingController _attendees;
  String? _calendarId;
  bool _addMeet = false;
  bool _allDay = false;
  late DateTime _start;
  late DateTime _end;
  String? _rrule;
  String? _colorId;
  String? _tzId;
  List<int> _reminders = [10];
  String? _alarmPreset;
  DraftAutosaver? _saver;
  bool _saved = false;
  SettingsRepository? _settings;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    final d = widget.restoredDraft;
    _title = TextEditingController(
      text: (d?['title'] as String?) ?? e?.title ?? '',
    );
    _location = TextEditingController(
      text: (d?['location'] as String?) ?? e?.location ?? '',
    );
    _notes = TextEditingController(
      text: (d?['notes'] as String?) ?? e?.notes ?? '',
    );
    _attendees = TextEditingController(
      text: (d?['attendees'] as String?) ?? '',
    );
    _calendarId = (d?['calendarId'] as String?) ?? e?.calendarId;
    _allDay = (d?['allDay'] as bool?) ?? e?.isAllDay ?? false;
    _colorId = (d?['colorId'] as String?) ?? e?.colorId;
    _tzId = (d?['tzId'] as String?) ?? e?.tzId;
    _addMeet = (d?['addMeet'] as bool?) ?? (e?.meetUrl != null);
    final draftReminders = (d?['reminders'] as List?)
        ?.whereType<num>()
        .map((x) => x.toInt())
        .toList();
    _reminders =
        draftReminders ??
        parseReminderOffsets(e?.reminders, allDay: e?.isAllDay ?? false);
    _alarmPreset = (d?['alarmPreset'] as String?) ?? e?.alarmPreset;
    if (e != null &&
        e.isAllDay &&
        e.startDate != null &&
        d?['startMs'] == null) {
      // Internally endDate is exclusive; show the inclusive last day.
      final start = _parseDateKey(e.startDate) ?? DateTime.now();
      _start = DateTime(start.year, start.month, start.day);
      final exclusiveEnd =
          _parseDateKey(e.endDate) ?? _start.add(const Duration(days: 1));
      var last = exclusiveEnd.subtract(const Duration(days: 1));
      // Legacy all-day rows stored endDate == startDate for one day.
      if (last.isBefore(_start)) last = _start;
      _end = DateTime(last.year, last.month, last.day);
    } else if (e?.startUtc != null && d?['startMs'] == null) {
      _start = DateTime.fromMillisecondsSinceEpoch(
        e!.startUtc!,
        isUtc: true,
      ).toLocal();
      _end = e.endUtc == null
          ? _start.add(const Duration(hours: 1))
          : DateTime.fromMillisecondsSinceEpoch(
              e.endUtc!,
              isUtc: true,
            ).toLocal();
    } else if (d?['startMs'] != null) {
      _start = DateTime.fromMillisecondsSinceEpoch(
        (d!['startMs'] as num).toInt(),
      );
      final endMs = (d['endMs'] as num?)?.toInt();
      _end = endMs == null
          ? _start.add(const Duration(hours: 1))
          : DateTime.fromMillisecondsSinceEpoch(endMs);
    } else {
      final day = widget.initialDay ?? DateTime.now();
      final hour = widget.initialHour ?? 9;
      _start = DateTime(day.year, day.month, day.day, hour);
      _end = _start.add(const Duration(hours: 1));
    }
    _rrule = (d?['rrule'] as String?) ?? e?.rrule;
    for (final c in [_title, _location, _notes, _attendees]) {
      c.addListener(_queueDraft);
    }
    if (d == null && e == null) Future.microtask(_preloadDraft);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _saver ??= DraftAutosaver(
      ref.read(draftStoreProvider),
      'event',
      _draftEntityId,
    );
    Future.microtask(() async {
      try {
        final repo = await ref.read(settingsRepositoryProvider.future);
        _settings = repo;
        await repo.setOpenSheet(
          widget.event == null ? 'event_new' : 'event:${widget.event!.id}',
        );
      } catch (_) {}
    });
  }

  void _applyDraft(Map<String, dynamic> j) {
    setState(() {
      _title.text = (j['title'] as String?) ?? '';
      _location.text = (j['location'] as String?) ?? '';
      _notes.text = (j['notes'] as String?) ?? '';
      _attendees.text = (j['attendees'] as String?) ?? '';
      _calendarId = j['calendarId'] as String?;
      _allDay = (j['allDay'] as bool?) ?? false;
      _colorId = j['colorId'] as String?;
      _tzId = j['tzId'] as String?;
      _addMeet = (j['addMeet'] as bool?) ?? false;
      final r = (j['reminders'] as List?)
          ?.whereType<num>()
          .map((x) => x.toInt())
          .toList();
      if (r != null && r.isNotEmpty) _reminders = r;
      _alarmPreset = j['alarmPreset'] as String?;
      final startMs = (j['startMs'] as num?)?.toInt();
      final endMs = (j['endMs'] as num?)?.toInt();
      if (startMs != null) {
        _start = DateTime.fromMillisecondsSinceEpoch(startMs);
      }
      if (endMs != null) _end = DateTime.fromMillisecondsSinceEpoch(endMs);
      _rrule = j['rrule'] as String?;
    });
  }

  void _changed(void Function() fn) {
    setState(fn);
    _queueDraft();
  }

  @override
  void dispose() {
    if (!_saved) {
      final snap = _snapshot();
      _saver?.changed(() => snap);
    }
    _saver?.dispose();
    final settings = _settings;
    // Normal close clears the marker; process kill skips dispose
    // so the marker survives kills. Drafts are kept for preload.
    if (settings != null) {
      final expected = _expectedSheet();
      Future.microtask(() async {
        try {
          if (settings.openSheet == expected) {
            await settings.setOpenSheet(null);
          }
        } catch (_) {}
      });
    }
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    _attendees.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildEventEditor(context);
}

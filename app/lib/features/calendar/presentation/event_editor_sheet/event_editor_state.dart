// Event editor widget and state: draft restore/autosave, save flow
// (including scope handling for recurring events), and the form build.
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

  String get _draftEntityId => widget.event?.id ?? 'new';

  bool get _isMicrosoftEvent {
    final e = widget.event;
    if (e == null) return false;
    final cals = ref.read(calendarsProvider).value ?? const <Calendar>[];
    Calendar? cal;
    for (final c in cals) {
      if (c.id == e.calendarId) {
        cal = c;
        break;
      }
    }
    if (cal == null && _calendarId != null) {
      for (final c in cals) {
        if (c.id == _calendarId) {
          cal = c;
          break;
        }
      }
    }
    return isMicrosoftEvent(
      eventMicrosoftAccount: e.microsoftAccount,
      calendarSource: cal?.source,
      calendarMicrosoftAccount: cal?.microsoftAccount,
    );
  }

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

  Future<void> _preloadDraft() async {
    if (!mounted || _title.text.isNotEmpty) return;
    try {
      final draft = await ref.read(draftStoreProvider).load('event', 'new');
      if (draft == null || !mounted || _title.text.isNotEmpty) return;
      if (draftIsExpired(
        draft.updatedAtMs,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      )) {
        return;
      }
      _applyDraft(draft.json);
    } catch (_) {}
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

  Map<String, dynamic> _snapshot() => {
    'title': _title.text,
    'location': _location.text,
    'notes': _notes.text,
    'attendees': _attendees.text,
    'calendarId': _calendarId,
    'allDay': _allDay,
    'colorId': _colorId,
    'tzId': _tzId,
    'addMeet': _addMeet,
    'reminders': _reminders,
    'alarmPreset': _alarmPreset,
    'startMs': _start.millisecondsSinceEpoch,
    'endMs': _end.millisecondsSinceEpoch,
    'rrule': _rrule,
  };

  void _queueDraft() => _saver?.changed(_snapshot);

  void _changed(void Function() fn) {
    setState(fn);
    _queueDraft();
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

  String _expectedSheet() =>
      widget.event == null ? 'event_new' : 'event:${widget.event!.id}';

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

  // _clearDraftAfterSave, _notesPayload, _persistOverflow, _pickDate,
  // _pickTime, and _save live in event_editor_save.dart (extension on
  // this state class).

  @override
  Widget build(BuildContext context) {
    final calsAsync = ref.watch(calendarsProvider);
    return SafeArea(
      child: Padding(
        padding: sheetPadding(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                autofocus: widget.event == null,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 8),
              calsAsync.maybeWhen(
                data: (cals) {
                  final calendar = _calendarId == null
                      ? null
                      : cals.where((c) => c.id == _calendarId).firstOrNull;
                  final source = calendar == null
                      ? 'Select calendar'
                      : sourceLabel(
                              name: calendar.name,
                              account: accountForSource(
                                googleAccount: calendar.googleAccount,
                                microsoftAccount: calendar.microsoftAccount,
                              ),
                              isLocal:
                                  calendar.source != 'google' &&
                                  calendar.source != 'microsoft',
                            ) ??
                            calendar.name;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: Text(source),
                    subtitle: const Text('Calendar source'),
                    trailing: const Icon(Icons.swap_horiz),
                    onTap: () async {
                      final picked = await showCalendarSourcePicker(
                        context,
                        ref,
                        selectedId: _calendarId,
                      );
                      if (picked != null) _changed(() => _calendarId = picked);
                    },
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              _EventWhenSection(
                allDay: _allDay,
                start: _start,
                end: _end,
                onToggleAllDay: (v) => _changed(() {
                  _allDay = v;
                  if (v) {
                    _start = DateTime(_start.year, _start.month, _start.day);
                    _end = DateTime(_end.year, _end.month, _end.day);
                    if (_end.isBefore(_start)) _end = _start;
                  } else {
                    if (!_end.isAfter(_start)) {
                      _end = _start.add(const Duration(hours: 1));
                    }
                  }
                }),
                onPickDate: (isStart) => _pickDate(isStart),
                onPickTime: (isStart) => _pickTime(isStart),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _repeatPresets.containsValue(_rrule)
                    ? _rrule
                    : '__custom__',
                decoration: const InputDecoration(
                  labelText: 'Repeat',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final e in _repeatPresets.entries)
                    DropdownMenuItem(value: e.value, child: Text(e.key)),
                  DropdownMenuItem(
                    value: '__custom__',
                    child: Text(
                      _rrule == null
                          ? 'Custom'
                          : 'Custom: ${_summarizeRrule(context, _rrule!)}',
                    ),
                  ),
                ],
                onChanged: (v) async {
                  if (v == '__custom__') {
                    final result = await _showCustomRepeatDialog(
                      context,
                      ref,
                      _rrule,
                    );
                    if (result != null) {
                      _changed(() => _rrule = result.isEmpty ? null : result);
                    }
                  } else {
                    _changed(() => _rrule = v);
                  }
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Add Google Meet'),
                value: _addMeet,
                onChanged: (v) => _changed(() => _addMeet = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _attendees,
                decoration: const InputDecoration(
                  labelText: 'Invitees (comma-separated emails)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Color'),
              _EventColorSection(
                colorId: _colorId,
                onChanged: (c) => _changed(() => _colorId = c),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _tzId,
                decoration: const InputDecoration(
                  labelText: 'Timezone',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: null,
                    child: Text('Floating (local)'),
                  ),
                  DropdownMenuItem(value: 'UTC', child: Text('UTC')),
                  DropdownMenuItem(
                    value: 'America/Sao_Paulo',
                    child: Text('America/Sao_Paulo'),
                  ),
                  DropdownMenuItem(
                    value: 'America/New_York',
                    child: Text('America/New_York'),
                  ),
                  DropdownMenuItem(
                    value: 'Europe/London',
                    child: Text('Europe/London'),
                  ),
                  DropdownMenuItem(
                    value: 'Asia/Tokyo',
                    child: Text('Asia/Tokyo'),
                  ),
                ],
                onChanged: (v) => _changed(() => _tzId = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _location,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              ReminderPicker(
                offsets: _reminders,
                onChanged: (v) => _changed(() => _reminders = v),
              ),
              const SizedBox(height: 8),
              AlarmPresetPicker(
                value: _alarmPreset,
                onChanged: (v) => _changed(() => _alarmPreset = v),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: (widget.event != null && _isMicrosoftEvent)
                    ? null
                    : () => _save(),
                child: Text(widget.event == null ? 'Create' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

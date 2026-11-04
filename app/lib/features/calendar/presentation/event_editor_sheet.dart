// Event editor: title, calendar, all-day/timed, timezone note,
// repeat presets, location, notes. Recurring edits ask scope.
// Unsaved input autosaves (debounced) and restores after restart.
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:ephemeron/core/ui/app_sheet.dart';
import 'package:ephemeron/core/ui/sheet_padding.dart';
import 'package:ephemeron/core/ui/escape_to_close.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session/session_restore.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../domain/alarms/alarm_preset.dart';
import '../../../domain/alarms/reminder.dart';
import '../../../core/platform/app_permissions.dart';
import '../../alarms/presentation/alarm_preset_picker.dart';
import '../../settings/application/settings_providers.dart';
import '../../notes/application/notes_providers.dart';
import '../application/calendar_providers.dart';
import '../../../domain/recurrence/recurrence_rule.dart';
import 'scope_sheet.dart';
import 'google_calendar_colors.dart';

Future<void> showEventEditor(
  BuildContext context, {
  Event? event,
  DateTime? initialDay,
  int? initialHour,
  Map<String, dynamic>? restoredDraft,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => EscapeToClose(
      child: _EventEditor(
        event: event,
        initialDay: initialDay,
        initialHour: initialHour,
        restoredDraft: restoredDraft,
      ),
    ),
  );
}

String _summarizeRrule(BuildContext context, String rrule) {
  try {
    final r = RecurrenceRule.parse(rrule);
    final freq = r.freq[0] + r.freq.substring(1).toLowerCase();
    final interval = r.interval > 1 ? ' every ${r.interval}' : '';
    final days = r.byDay.isNotEmpty ? ' on ${r.byDay.join(', ')}' : '';
    final end = r.count != null
        ? ' for ${r.count} times'
        : r.untilUtc != null
        ? ' until ${DeviceDateFormat.yMMMd(context).format(r.untilUtc!.toLocal())}'
        : r.untilDate != null
        ? ' until ${r.untilDate}'
        : '';
    return '$freq$interval$days$end';
  } catch (_) {
    return rrule;
  }
}

const _repeatPresets = {
  'Does not repeat': null,
  'Daily': 'FREQ=DAILY',
  'Weekly': 'FREQ=WEEKLY',
  'Monthly': 'FREQ=MONTHLY',
  'Yearly': 'FREQ=YEARLY',
  'Last day of month': 'FREQ=MONTHLY;BYMONTHDAY=-1',
};

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
  dynamic _settings;

  String get _draftEntityId => widget.event?.id ?? 'new';

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
    if (e?.startUtc != null && d?['startMs'] == null) {
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

  Future<void> _clearDraftAfterSave() async {
    _saved = true;
    try {
      await ref.read(draftStoreProvider).clear('event', _draftEntityId);
      final srepo = await ref.read(settingsRepositoryProvider.future);
      final expected = widget.event == null
          ? 'event_new'
          : 'event:${widget.event!.id}';
      if (srepo.openSheet == expected) await srepo.setOpenSheet(null);
    } catch (_) {}
  }

  Future<void> _pickDate(bool isStart) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    _changed(() {
      if (isStart) {
        _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute);
        if (_end.isBefore(_start)) {
          _end = _start.add(const Duration(hours: 1));
        }
      } else {
        _end = DateTime(d.year, d.month, d.day, _end.hour, _end.minute);
        if (_end.isBefore(_start)) {
          _end = _start.add(const Duration(hours: 1));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('End was before start; adjusted.')),
          );
        }
      }
    });
  }

  Future<void> _pickTime(bool isStart) async {
    final t = await awaitTime(context, isStart ? _start : _end);
    if (t == null) return;
    _changed(() {
      if (isStart) {
        final dur = _end.difference(_start);
        _start = DateTime(
          _start.year,
          _start.month,
          _start.day,
          t.hour,
          t.minute,
        );
        _end = _start.add(dur);
      } else {
        _end = DateTime(_end.year, _end.month, _end.day, t.hour, t.minute);
      }
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Title is required.')));
      return;
    }
    if (_calendarId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a calendar.')));
      return;
    }
    // Moment of need: reminders/alarms only prompt here, at save time.
    // Advisory only: the save always proceeds, alerts may stay silent.
    if (_reminders.isNotEmpty || _alarmPreset != null) {
      final preset = AlarmPreset.tryParse(_alarmPreset);
      await AppPermissions.ensureAlarmPrereqs(
        context,
        exactAlarm: preset?.needsAlarmClock ?? false,
        fullScreen: preset?.usesFullScreen ?? false,
      );
      if (!mounted) return;
    }
    final repo = ref.read(eventRepositoryProvider);
    // Conflict hint: warn if overlapping a busy event.
    if (!_allDay) {
      final overlaps = await repo.overlappingEvents(
        calendarId: _calendarId!,
        startUtc: _start.toUtc(),
        endUtc: _end.toUtc(),
        excludeId: widget.event?.id,
      );
      if (overlaps.isNotEmpty && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Scheduling conflict'),
            content: Text(
              'This overlaps ${overlaps.length} existing event(s). Save anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }
    final noteRepo = ref.read(noteRepositoryProvider);
    final settings = await ref.read(settingsRepositoryProvider.future);
    _calendarId ??= settings.defaultCalendarId;
    final existing = widget.event;
    if (existing == null || existing.rrule == null) {
      if (existing == null) {
        final fullNotes = _notes.text.trim().isEmpty
            ? null
            : _notes.text.trim();
        final eventId = await repo.createEvent(
          calendarId: _calendarId!,
          title: title,
          startUtc: _allDay ? null : _start.toUtc(),
          endUtc: _allDay ? null : _end.toUtc(),
          startDate: _allDay ? _fmtDate(_start) : null,
          allDay: _allDay,
          // SECURITY: store null (floating local time) for device-created
          // events. DateTime.now().timeZoneName yields abbreviations like
          // "-03" that are not IANA ids and crash tz.getLocation lookups.
          tzId: _tzId,
          colorId: _colorId,
          createMeet: _addMeet,
          rrule: _rrule,
          location: _location.text.trim().isEmpty
              ? null
              : _location.text.trim(),
          notes: fullNotes != null && fullNotes.length > 8000
              ? '${fullNotes.substring(0, 8000)}\n(continued in Ephemeron)'
              : fullNotes,
          reminders: encodeReminderOffsets(_reminders),
          alarmPreset: _alarmPreset,
        );
        if (fullNotes != null && fullNotes.length > 8000) {
          final noteId = await noteRepo.ensureOverflowNote(eventId, fullNotes);
          await repo.setNotesOverflow(eventId, noteId);
        }
        await repo.setAttendees(eventId, _attendees.text.split(','));
      } else {
        await repo.editOccurrence(
          existing.id,
          existing.startUtc == null
              ? DateTime.now().toUtc()
              : DateTime.fromMillisecondsSinceEpoch(
                  existing.startUtc!,
                  isUtc: true,
                ),
          scope: EditScope.all,
          title: title,
          startUtc: _allDay ? null : _start.toUtc(),
          endUtc: _allDay ? null : _end.toUtc(),
          location: _location.text.trim().isEmpty
              ? null
              : _location.text.trim(),
          colorId: _colorId,
          tzId: _tzId,
          createMeet: _addMeet,
          reminders: () => encodeReminderOffsets(_reminders),
          alarmPreset: () => _alarmPreset,
        );
      }
      await repo.setAttendees(existing!.id, _attendees.text.split(','));
      await _clearDraftAfterSave();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    final scope = await showScopeSheet(
      context,
      allowSingle: _rrule == existing.rrule,
    );
    if (scope == null) return;
    if (!mounted) return;
    if (scope == EditScope.all &&
        (_start.toUtc().millisecondsSinceEpoch != existing.startUtc ||
            _end.toUtc().millisecondsSinceEpoch != existing.endUtc)) {
      final keep =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Keep per-event changes?'),
              content: const Text(
                'Some occurrences were changed individually.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Keep'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ) ??
          true;
      if (!mounted) return;
      await repo.editOccurrence(
        existing.id,
        DateTime.fromMillisecondsSinceEpoch(existing.startUtc!, isUtc: true),
        scope: EditScope.all,
        title: title,
        startUtc: _allDay ? null : _start.toUtc(),
        endUtc: _allDay ? null : _end.toUtc(),
        rrule: () => _rrule,
        resetExceptions: !keep,
      );
      await repo.setAttendees(existing.id, _attendees.text.split(','));
      await _clearDraftAfterSave();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await repo.editOccurrence(
      existing.id,
      DateTime.fromMillisecondsSinceEpoch(existing.startUtc!, isUtc: true),
      scope: scope,
      title: title,
      startUtc: _allDay ? null : _start.toUtc(),
      endUtc: _allDay ? null : _end.toUtc(),
      rrule: scope == EditScope.single ? null : () => _rrule,
    );
    if (mounted) {
      try {
        final range = ref.read(calendarCacheRangeProvider);
        await ref
            .read(occurrenceRepositoryProvider)
            .rebuildWindow(
              windowStartUtc: range.fromUtc,
              windowEndUtc: range.toUtc,
            );
      } catch (_) {
        // Best-effort; next navigation rebuilds.
      }
      await _clearDraftAfterSave();
      if (mounted) Navigator.of(context).pop();
    }
  }

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
                  final groups = <String, List<Calendar>>{};
                  for (final c in cals) {
                    groups
                        .putIfAbsent(
                          c.source == 'google'
                              ? (c.googleAccount ?? 'Google')
                              : 'Device',
                          () => [],
                        )
                        .add(c);
                  }
                  final items = <DropdownMenuItem<String?>>[];
                  for (final entry in groups.entries) {
                    items.add(
                      DropdownMenuItem<String?>(
                        enabled: false,
                        child: Text(
                          entry.key,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                    for (final c in entry.value) {
                      items.add(
                        DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text('  ${c.name}'),
                        ),
                      );
                    }
                  }
                  return DropdownButtonFormField<String?>(
                    initialValue: _calendarId,
                    decoration: const InputDecoration(
                      labelText: 'Calendar',
                      border: OutlineInputBorder(),
                    ),
                    items: items,
                    onChanged: (v) => _changed(() => _calendarId = v),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _allDay,
                onChanged: (v) => _changed(() => _allDay = v),
                title: const Text('All day'),
                contentPadding: EdgeInsets.zero,
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(true),
                      child: Text(
                        DeviceDateFormat.yMMMd(context).format(_start),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!_allDay)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickTime(true),
                        child: Text(_fmtTime(_start)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(false),
                      child: Text(DeviceDateFormat.yMMMd(context).format(_end)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!_allDay)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickTime(false),
                        child: Text(_fmtTime(_end)),
                      ),
                    ),
                ],
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
                    // Parse existing rrule into builder state.
                    String freq = 'WEEKLY';
                    int interval = 1;
                    final byDay = <String>{};
                    int? monthDay;
                    String endMode = 'never';
                    int count = 10;
                    DateTime? until;
                    if (_rrule != null && _rrule!.isNotEmpty) {
                      try {
                        final r = RecurrenceRule.parse(_rrule!);
                        freq = r.freq;
                        interval = r.interval;
                        byDay.addAll(r.byDay);
                        if (r.byMonthDay.isNotEmpty) {
                          monthDay = r.byMonthDay.first;
                        }
                        if (r.count != null) {
                          endMode = 'count';
                          count = r.count!;
                        } else if (r.untilUtc != null || r.untilDate != null) {
                          endMode = 'until';
                          if (r.untilUtc != null) {
                            until = r.untilUtc;
                          } else if (r.untilDate != null) {
                            final p = r.untilDate!.split('-');
                            until = DateTime(
                              int.parse(p[0]),
                              int.parse(p[1]),
                              int.parse(p[2]),
                            );
                          }
                        }
                      } catch (_) {}
                    }
                    final result = await showDialog<String>(
                      context: context,
                      builder: (ctx) => StatefulBuilder(
                        builder: (ctx, setSt) => AlertDialog(
                          title: const Text('Custom repeat'),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DropdownButtonFormField<String>(
                                  initialValue: freq,
                                  decoration: const InputDecoration(
                                    labelText: 'Frequency',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'DAILY',
                                      child: Text('Daily'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'WEEKLY',
                                      child: Text('Weekly'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'MONTHLY',
                                      child: Text('Monthly'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'YEARLY',
                                      child: Text('Yearly'),
                                    ),
                                  ],
                                  onChanged: (x) => setSt(() => freq = x!),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Text('Every'),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 60,
                                      child: TextField(
                                        controller: TextEditingController(
                                          text: interval.toString(),
                                        ),
                                        keyboardType: TextInputType.number,
                                        onChanged: (t) =>
                                            interval = int.tryParse(t) ?? 1,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      freq == 'DAILY'
                                          ? 'day(s)'
                                          : freq == 'WEEKLY'
                                          ? 'week(s)'
                                          : freq == 'MONTHLY'
                                          ? 'month(s)'
                                          : 'year(s)',
                                    ),
                                  ],
                                ),
                                if (freq == 'WEEKLY') ...[
                                  const SizedBox(height: 8),
                                  const Text('On days'),
                                  Wrap(
                                    spacing: 4,
                                    children: [
                                      for (final d in const [
                                        'MO',
                                        'TU',
                                        'WE',
                                        'TH',
                                        'FR',
                                        'SA',
                                        'SU',
                                      ])
                                        FilterChip(
                                          label: Text(d),
                                          selected: byDay.contains(d),
                                          onSelected: (sel) => setSt(() {
                                            if (sel) {
                                              byDay.add(d);
                                            } else {
                                              byDay.remove(d);
                                            }
                                          }),
                                        ),
                                    ],
                                  ),
                                ],
                                if (freq == 'MONTHLY') ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Text('Day of month:'),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 60,
                                        child: TextField(
                                          controller: TextEditingController(
                                            text: (monthDay ?? 1).toString(),
                                          ),
                                          keyboardType: TextInputType.number,
                                          onChanged: (t) =>
                                              monthDay = int.tryParse(t),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('(-1 = last day)'),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue: endMode,
                                  decoration: const InputDecoration(
                                    labelText: 'Ends',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'never',
                                      child: Text('Never'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'count',
                                      child: Text('After N times'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'until',
                                      child: Text('On date'),
                                    ),
                                  ],
                                  onChanged: (x) => setSt(() => endMode = x!),
                                ),
                                if (endMode == 'count') ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Text('Times:'),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 60,
                                        child: TextField(
                                          controller: TextEditingController(
                                            text: count.toString(),
                                          ),
                                          keyboardType: TextInputType.number,
                                          onChanged: (t) =>
                                              count = int.tryParse(t) ?? count,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (endMode == 'until') ...[
                                  const SizedBox(height: 8),
                                  OutlinedButton(
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: ctx,
                                        initialDate: until ?? DateTime.now(),
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        setSt(() => until = picked);
                                      }
                                    },
                                    child: Text(
                                      until == null
                                          ? 'Pick date'
                                          : DeviceDateFormat.yMMMd(
                                              ctx,
                                            ).format(until!),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () {
                                final parts = <String>['FREQ=$freq'];
                                if (interval > 1) {
                                  parts.add('INTERVAL=$interval');
                                }
                                if (freq == 'WEEKLY' && byDay.isNotEmpty) {
                                  parts.add('BYDAY=${byDay.join(',')}');
                                }
                                if (freq == 'MONTHLY' && monthDay != null) {
                                  parts.add('BYMONTHDAY=$monthDay');
                                }
                                if (endMode == 'count') {
                                  parts.add('COUNT=$count');
                                } else if (endMode == 'until' &&
                                    until != null) {
                                  parts.add(
                                    'UNTIL=${until!.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first}Z',
                                  );
                                }
                                Navigator.of(ctx).pop(parts.join(';'));
                              },
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      ),
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
              Wrap(
                spacing: 8,
                children: [
                  for (final c in const [
                    null,
                    '1',
                    '2',
                    '3',
                    '4',
                    '5',
                    '6',
                    '7',
                    '8',
                    '9',
                    '10',
                    '11',
                  ])
                    GestureDetector(
                      onTap: () => _changed(() => _colorId = c),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: c == null
                            ? Theme.of(context).colorScheme.primary
                            : googleCalendarColor(c),
                        child: _colorId == c
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                ],
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
                onPressed: _save,
                child: Text(widget.event == null ? 'Create' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

Future<TimeOfDay?> awaitTime(BuildContext context, DateTime d) {
  return showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: d.hour, minute: d.minute),
  );
}

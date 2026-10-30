// Event editor: title, calendar, all-day/timed, timezone note,
// repeat presets, location, notes. Recurring edits ask scope.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../../data/repositories/event_repository.dart';
import '../../settings/application/settings_providers.dart';
import '../../notes/application/notes_providers.dart';
import '../application/calendar_providers.dart';
import '../../../domain/recurrence/recurrence_rule.dart';
import 'scope_sheet.dart';

Future<void> showEventEditor(
  BuildContext context, {
  Event? event,
  DateTime? initialDay,
  int? initialHour,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EventEditor(
      event: event,
      initialDay: initialDay,
      initialHour: initialHour,
    ),
  );
}

const _googleColorMap = <String, Color>{
  '1': Color(0xFF7986CB),
  '2': Color(0xFF33B679),
  '3': Color(0xFF8E24AA),
  '4': Color(0xFFE67C73),
  '5': Color(0xFFF6BF26),
  '6': Color(0xFF3F51B5),
  '7': Color(0xFF039BE5),
  '8': Color(0xFF0B8043),
  '9': Color(0xFFD50000),
  '10': Color(0xFF303F9F),
  '11': Color(0xFF616161),
};

Color _googleColor(String id) => _googleColorMap[id] ?? Colors.blue;

String _summarizeRrule(String rrule) {
  try {
    final r = RecurrenceRule.parse(rrule);
    final freq = r.freq[0] + r.freq.substring(1).toLowerCase();
    final interval = r.interval > 1 ? ' every ${r.interval}' : '';
    final days = r.byDay.isNotEmpty ? ' on ${r.byDay.join(', ')}' : '';
    final end = r.count != null
        ? ' for ${r.count} times'
        : r.untilUtc != null
        ? ' until ${r.untilUtc!.toLocal().toString().split(' ').first}'
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
  const _EventEditor({this.event, this.initialDay, this.initialHour});

  final Event? event;
  final DateTime? initialDay;
  final int? initialHour;

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

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _title = TextEditingController(text: e?.title ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _attendees = TextEditingController();
    _calendarId = e?.calendarId;
    _allDay = e?.isAllDay ?? false;
    _colorId = e?.colorId;
    _tzId = e?.tzId;
    _addMeet = e?.meetUrl != null;
    if (e?.startUtc != null) {
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
    } else {
      final day = widget.initialDay ?? DateTime.now();
      final hour = widget.initialHour ?? 9;
      _start = DateTime(day.year, day.month, day.day, hour);
      _end = _start.add(const Duration(hours: 1));
    }
    _rrule = e?.rrule;
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    _attendees.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
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
    setState(() {
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
    if (title.isEmpty || _calendarId == null) return;
    final repo = ref.read(eventRepositoryProvider);
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
        );
      }
      await repo.setAttendees(existing!.id, _attendees.text.split(','));
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
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final calsAsync = ref.watch(calendarsProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
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
                    groups.putIfAbsent(
                      c.source == 'google' ? 'Google' : 'Device',
                      () => [],
                    ).add(c);
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
                    onChanged: (v) => setState(() => _calendarId = v),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _allDay,
                onChanged: (v) => setState(() => _allDay = v),
                title: const Text('All day'),
                contentPadding: EdgeInsets.zero,
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(true),
                      child: Text(_fmtDate(_start)),
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
                      child: Text(_fmtDate(_end)),
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
                          : 'Custom: ${_summarizeRrule(_rrule!)}',
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
                                          onChanged: (t) => monthDay =
                                              int.tryParse(t),
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
                                  onChanged: (x) =>
                                      setSt(() => endMode = x!),
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
                                          : '${until!.year}-${until!.month.toString().padLeft(2, '0')}-${until!.day.toString().padLeft(2, '0')}',
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
                                } else if (endMode == 'until' && until != null) {
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
                      setState(() => _rrule = result.isEmpty ? null : result);
                    }
                  } else {
                    setState(() => _rrule = v);
                  }
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Add Google Meet'),
                value: _addMeet,
                onChanged: (v) => setState(() => _addMeet = v),
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
                      onTap: () => setState(() => _colorId = c),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: c == null
                            ? Theme.of(context).colorScheme.primary
                            : _googleColor(c),
                        child: _colorId == c
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
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
                  DropdownMenuItem(value: null, child: Text('Floating (local)')),
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
                onChanged: (v) => setState(() => _tzId = v),
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

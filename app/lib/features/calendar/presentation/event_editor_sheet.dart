// Event editor: title, calendar, all-day/timed, timezone note,
// repeat presets, location, notes. Recurring edits ask scope.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../../data/repositories/event_repository.dart';
import '../../settings/application/settings_providers.dart';
import '../../notes/application/notes_providers.dart';
import '../application/calendar_providers.dart';
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
  String? _calendarId;
  bool _allDay = false;
  late DateTime _start;
  late DateTime _end;
  String? _rrule;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _title = TextEditingController(text: e?.title ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _calendarId = e?.calendarId;
    _allDay = e?.isAllDay ?? false;
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
          tzId: _allDay ? null : DateTime.now().timeZoneName,
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
        );
      }
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
                data: (cals) => DropdownButtonFormField<String?>(
                  initialValue: _calendarId,
                  decoration: const InputDecoration(
                    labelText: 'Calendar',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final c in cals)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _calendarId = v),
                ),
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
                  const DropdownMenuItem(
                    value: '__custom__',
                    child: Text('Custom RRULE'),
                  ),
                ],
                onChanged: (v) async {
                  if (v == '__custom__') {
                    final ctl = TextEditingController(text: _rrule ?? '');
                    final custom = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Custom RRULE'),
                        content: TextField(controller: ctl, autofocus: true),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(ctx).pop(ctl.text.trim()),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                    if (custom != null) {
                      setState(() => _rrule = custom.isEmpty ? null : custom);
                    }
                  } else {
                    setState(() => _rrule = v);
                  }
                },
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

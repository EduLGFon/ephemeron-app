// Task create/edit sheet with list, priority, due chips, tags, subtasks.
// Unsaved input autosaves (debounced) and restores after restart.
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:ephemeron/core/ui/app_sheet.dart';
import 'package:ephemeron/core/ui/sheet_padding.dart';
import 'package:ephemeron/core/ui/escape_to_close.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session/session_restore.dart';
import '../../../data/drift/app_database.dart';
import '../../../domain/alarms/alarm_preset.dart';
import '../../../domain/alarms/reminder.dart';
import '../../../domain/recurrence/recurrence_rule.dart';
import '../../../domain/sources/source_label.dart';
import '../../../domain/sources/source_move.dart';
import '../../../core/platform/app_permissions.dart';
import '../../alarms/presentation/alarm_preset_picker.dart';
import '../../settings/application/settings_providers.dart';
import '../application/tasks_providers.dart';
import 'task_source_picker.dart';

Future<void> showTaskEditor(
  BuildContext context, {
  Task? task,
  String? parentId,
  Map<String, dynamic>? restoredDraft,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => EscapeToClose(
      child: _TaskEditor(
        task: task,
        parentId: parentId,
        restoredDraft: restoredDraft,
      ),
    ),
  );
}

class _TaskEditor extends ConsumerStatefulWidget {
  const _TaskEditor({this.task, this.parentId, this.restoredDraft});

  final Task? task;
  final String? parentId;
  final Map<String, dynamic>? restoredDraft;

  @override
  ConsumerState<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<_TaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _tags;
  String? _listId;
  int _priority = 0;
  String? _dueDate;
  String? _plannedDate;
  String? _plannedStart;
  String? _plannedEnd;
  String? _rrule;
  final TextEditingController _rruleText = TextEditingController();
  int? _dueTime;
  bool _pinned = false;
  String? _alarmPreset;
  bool _customRrule = false;
  static const Map<String, String?> _repeatPresets = {
    'Does not repeat': null,
    'Daily': 'FREQ=DAILY',
    'Weekly': 'FREQ=WEEKLY',
    'Monthly': 'FREQ=MONTHLY',
    'Yearly': 'FREQ=YEARLY',
    'Custom RRULE': '__custom__',
  };
  List<int> _reminders = const [0];
  DraftAutosaver? _saver;
  bool _saved = false;
  dynamic _settings;

  String get _draftEntityId => widget.task?.id ?? 'new';

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    final d = widget.restoredDraft;
    _title = TextEditingController(
      text: (d?['title'] as String?) ?? t?.title ?? '',
    );
    _notes = TextEditingController(
      text: (d?['notes'] as String?) ?? t?.notes ?? '',
    );
    _tags = TextEditingController(text: (d?['tags'] as String?) ?? '');
    _listId = (d?['listId'] as String?) ?? t?.listId;
    _priority = (d?['priority'] as num?)?.toInt() ?? t?.priority ?? 0;
    _dueDate = (d?['dueDate'] as String?) ?? t?.dueDate;
    _plannedDate = (d?['plannedDate'] as String?) ?? t?.plannedDate;
    _plannedStart = (d?['plannedStart'] as String?) ?? t?.plannedStart;
    _plannedEnd = (d?['plannedEnd'] as String?) ?? t?.plannedEnd;
    _rrule = (d?['rrule'] as String?) ?? t?.rrule;
    _customRrule = _rrule != null && !_repeatPresets.containsValue(_rrule);
    _rruleText.text = _rrule ?? '';
    _dueTime = (d?['dueTime'] as num?)?.toInt() ?? t?.dueTime;
    _pinned = (d?['pinned'] as bool?) ?? t?.pinned ?? false;
    _alarmPreset = (d?['alarmPreset'] as String?) ?? t?.alarmPreset;
    final draftReminders = (d?['reminders'] as List?)
        ?.whereType<num>()
        .map((e) => e.toInt())
        .toList();
    _reminders = draftReminders != null && draftReminders.isNotEmpty
        ? draftReminders
        : (t?.reminders == null || t!.reminders!.trim().isEmpty
              ? const [0]
              : parseReminderOffsets(t.reminders));
    for (final c in [_title, _notes, _tags]) {
      c.addListener(_queueDraft);
    }
    if (d == null && t == null) Future.microtask(_preloadDraft);
  }

  Future<void> _preloadDraft() async {
    if (!mounted || _title.text.isNotEmpty || _notes.text.isNotEmpty) return;
    try {
      final draft = await ref.read(draftStoreProvider).load('task', 'new');
      if (draft == null || !mounted) return;
      if (draftIsExpired(
        draft.updatedAtMs,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      )) {
        return;
      }
      final j = draft.json;
      final title = j['title'] as String?;
      if (title == null || title.isEmpty) return;
      setState(() {
        _title.text = title;
        _notes.text = (j['notes'] as String?) ?? '';
        _tags.text = (j['tags'] as String?) ?? '';
        _listId = j['listId'] as String?;
        _priority = (j['priority'] as num?)?.toInt() ?? 0;
        _dueDate = j['dueDate'] as String?;
        _plannedDate = j['plannedDate'] as String?;
        _plannedStart = j['plannedStart'] as String?;
        _plannedEnd = j['plannedEnd'] as String?;
        _rrule = j['rrule'] as String?;
        _customRrule = _rrule != null && !_repeatPresets.containsValue(_rrule);
        _rruleText.text = _rrule ?? '';
        _dueTime = (j['dueTime'] as num?)?.toInt();
        _pinned = (j['pinned'] as bool?) ?? false;
        _alarmPreset = j['alarmPreset'] as String?;
      });
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _saver ??= DraftAutosaver(
      ref.read(draftStoreProvider),
      'task',
      _draftEntityId,
    );
    Future.microtask(() async {
      try {
        final repo = await ref.read(settingsRepositoryProvider.future);
        _settings = repo;
        await repo.setOpenSheet(
          widget.task == null ? 'task_new' : 'task:${widget.task!.id}',
        );
      } catch (_) {}
    });
  }

  void _queueDraft() {
    _saver?.changed(
      () => {
        'title': _title.text,
        'notes': _notes.text,
        'tags': _tags.text,
        'listId': _listId,
        'priority': _priority,
        'dueDate': _dueDate,
        'plannedDate': _plannedDate,
        'plannedStart': _plannedStart,
        'plannedEnd': _plannedEnd,
        'rrule': _rrule,
        'dueTime': _dueTime,
        'pinned': _pinned,
        'alarmPreset': _alarmPreset,
        'reminders': _reminders,
        'parentId': widget.parentId,
      },
    );
  }

  String _expectedSheet() =>
      widget.task == null ? 'task_new' : 'task:${widget.task!.id}';

  @override
  void dispose() {
    if (!_saved) {
      final snapshot = {
        'title': _title.text,
        'notes': _notes.text,
        'tags': _tags.text,
        'listId': _listId,
        'priority': _priority,
        'dueDate': _dueDate,
        'plannedDate': _plannedDate,
        'plannedStart': _plannedStart,
        'plannedEnd': _plannedEnd,
        'rrule': _rrule,
        'dueTime': _dueTime,
        'pinned': _pinned,
        'alarmPreset': _alarmPreset,
        'reminders': _reminders,
        'parentId': widget.parentId,
      };
      _saver?.changed(() => snapshot);
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
    _notes.dispose();
    _tags.dispose();
    _rruleText.dispose();
    super.dispose();
  }

  String _fmtDue(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Title is required.')));
      return;
    }
    // Moment of need, advisory only: the save always proceeds.
    if (_reminders.isNotEmpty || _alarmPreset != null) {
      final preset = AlarmPreset.tryParse(_alarmPreset);
      await AppPermissions.ensureAlarmPrereqs(
        context,
        exactAlarm: preset?.needsAlarmClock ?? false,
        fullScreen: preset?.usesFullScreen ?? false,
      );
      if (!mounted) return;
    }
    if (_plannedStart != null && _plannedEnd != null) {
      final s = DateTime.tryParse(_plannedStart!);
      final e = DateTime.tryParse(_plannedEnd!);
      if (s != null && e != null && !e.isAfter(s)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Planned end must be after start.')),
          );
        }
        return;
      }
    }
    if (_rrule != null &&
        _rrule!.trim().isNotEmpty &&
        !_isValidRrule(_rrule!)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid recurrence rule.')),
        );
      }
      return;
    }
    final repo = ref.read(taskRepositoryProvider);
    final tagNames = _tags.text
        .split(RegExp(r'[,\s]+'))
        .map((s) => s.replaceAll('#', '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final existing = widget.task;
    // A timed planned interval replaces the legacy all-day planned date.
    final plannedDate = _plannedStart == null ? _plannedDate : null;
    if (existing == null) {
      await repo.createTask(
        title: title,
        listId: _listId,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        priority: _priority,
        dueDate: _dueDate,
        plannedDate: plannedDate,
        plannedStart: _plannedStart,
        plannedEnd: _plannedEnd,
        rrule: _rrule,
        dueTime: _dueTime,
        pinned: _pinned,
        parentId: widget.parentId,
        tags: tagNames,
        alarmPreset: _alarmPreset,
        reminders: encodeReminderOffsets(_reminders),
      );
    } else {
      if (existing.listId != _listId) {
        try {
          await repo.moveTasks([existing.id], _listId);
        } on SourceMoveException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(e.message)));
          }
          return;
        }
      }
      await repo.updateTask(
        existing.id,
        title: title,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        priority: _priority,
        dueDate: () => _dueDate,
        plannedDate: () => plannedDate,
        plannedStart: () => _plannedStart,
        plannedEnd: () => _plannedEnd,
        rrule: () => _rrule,
        dueTime: () => _dueTime,
        pinned: _pinned,
        alarmPreset: () => _alarmPreset,
        reminders: () => encodeReminderOffsets(_reminders),
      );
      if (tagNames.isNotEmpty) {
        await repo.setTaskTags(existing.id, tagNames);
      }
    }
    try {
      ref.read(occurrenceDirtyProvider.notifier).markDirty();
    } catch (_) {}
    _saved = true;
    try {
      await ref.read(draftStoreProvider).clear('task', _draftEntityId);
      final srepo = await ref.read(settingsRepositoryProvider.future);
      final expected = widget.task == null
          ? 'task_new'
          : 'task:${widget.task!.id}';
      if (srepo.openSheet == expected) await srepo.setOpenSheet(null);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final listsAsync = ref.watch(taskListsProvider);
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
                autofocus: widget.task == null,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
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
              listsAsync.maybeWhen(
                data: (lists) {
                  final list = _listId == null
                      ? null
                      : lists.where((l) => l.id == _listId).firstOrNull;
                  final source = list == null
                      ? 'No list'
                      : sourceLabel(
                              name: list.name,
                              account: list.googleAccount,
                              isLocal: list.googleAccount == null,
                            ) ??
                            list.name;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.list_alt_outlined),
                    title: Text(source),
                    subtitle: const Text('List source'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_listId != null)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'No list',
                            onPressed: () {
                              setState(() => _listId = null);
                              _queueDraft();
                            },
                          ),
                        const Icon(Icons.swap_horiz),
                      ],
                    ),
                    onTap: () async {
                      final picked = await showTaskListSourcePicker(
                        context,
                        ref,
                        selectedId: _listId,
                      );
                      if (picked == null) return;
                      setState(() => _listId = picked);
                      _queueDraft();
                    },
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Priority'),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final option in const [
                        (value: 0, label: 'None'),
                        (value: 1, label: 'P4'),
                        (value: 2, label: 'P3'),
                        (value: 3, label: 'P2'),
                        (value: 4, label: 'P1'),
                      ])
                        ChoiceChip(
                          label: Text(option.label),
                          selected: _priority == option.value,
                          onSelected: (_) {
                            setState(() => _priority = option.value);
                            _queueDraft();
                          },
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _dateRow(
                context,
                label: 'Planned date',
                value: _plannedDate,
                onChanged: (v) {
                  setState(() {
                    _plannedDate = v;
                    if (v != null) {
                      _plannedStart = null;
                      _plannedEnd = null;
                    }
                  });
                  _queueDraft();
                },
              ),
              const SizedBox(height: 8),
              _plannedIntervalSection(context),
              const SizedBox(height: 8),
              _repeatSection(context),
              const SizedBox(height: 8),
              _dateRow(
                context,
                label: 'Due date',
                value: _dueDate,
                onChanged: (v) {
                  setState(() => _dueDate = v);
                  _queueDraft();
                },
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  _dueChip(context, 'Today', _fmtDue(DateTime.now())),
                  _dueChip(
                    context,
                    'Tomorrow',
                    _fmtDue(DateTime.now().add(const Duration(days: 1))),
                  ),
                  _dueChip(
                    context,
                    'Next Mon',
                    _fmtDue(_nextWeekday(DateTime.now(), DateTime.monday)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tags,
                decoration: const InputDecoration(
                  labelText: 'Tags (space separated)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _dueTime == null
                          ? 'No time (9:00 reminder)'
                          : 'Time ${_pad(_dueTime! ~/ 60)}:${_pad(_dueTime! % 60)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: (_dueTime ?? 540) ~/ 60,
                          minute: (_dueTime ?? 540) % 60,
                        ),
                      );
                      if (t != null) {
                        setState(() => _dueTime = t.hour * 60 + t.minute);
                        _queueDraft();
                      }
                    },
                    child: const Text('Set time'),
                  ),
                  if (_dueTime != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear time',
                      onPressed: () {
                        setState(() => _dueTime = null);
                        _queueDraft();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ReminderPicker(
                offsets: _reminders,
                onChanged: (v) {
                  setState(() => _reminders = v.isEmpty ? const [0] : v);
                  _queueDraft();
                },
              ),
              const SizedBox(height: 8),
              AlarmPresetPicker(
                value: _alarmPreset,
                onChanged: (v) {
                  setState(() => _alarmPreset = v);
                  _queueDraft();
                },
              ),
              const SizedBox(height: 4),
              const Text(
                'Tasks always notify at the due time. The alarm adds a stronger alert.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _pinned,
                onChanged: (v) {
                  setState(() => _pinned = v);
                  _queueDraft();
                },
                title: const Text('Pinned'),
                contentPadding: EdgeInsets.zero,
              ),
              if (widget.task != null) _SubtaskSection(task: widget.task!),
              FilledButton(
                onPressed: _save,
                child: Text(widget.task == null ? 'Create' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateRow(
    BuildContext context, {
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_outlined),
      title: Text(label),
      subtitle: Text(
        value == null ? 'Not set' : DeviceDateFormat.dateIso(context, value),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Pick $label',
            onPressed: () => _pickDate(value, onChanged),
          ),
          if (value != null)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear $label',
              onPressed: () => onChanged(null),
            ),
        ],
      ),
      onTap: () => _pickDate(value, onChanged),
    );
  }

  Future<void> _pickDate(
    String? current,
    ValueChanged<String?> onChanged,
  ) async {
    final now = DateTime.now();
    final initial = current == null ? now : DateTime.tryParse(current) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onChanged(_fmtDue(picked));
  }

  Future<String?> _pickDateTime(String? current) async {
    final now = DateTime.now();
    final initial = current == null ? now : DateTime.tryParse(current) ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return '${_fmtDue(date)}T${_pad(time.hour)}:${_pad(time.minute)}';
  }

  Widget _plannedIntervalSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('Planned interval'),
          subtitle: Text(
            _plannedStart == null && _plannedEnd == null
                ? 'Not set'
                : '${_plannedStart ?? ''} - ${_plannedEnd ?? ''}',
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  final v = await _pickDateTime(_plannedStart);
                  if (v == null) return;
                  setState(() {
                    _plannedStart = v;
                    _plannedDate = null;
                    if (_plannedEnd != null) {
                      final s = DateTime.tryParse(v);
                      final e = DateTime.tryParse(_plannedEnd!);
                      if (s != null && e != null && !e.isAfter(s)) {
                        _plannedEnd = null;
                      }
                    }
                  });
                  _queueDraft();
                },
                child: Text(_plannedStart == null ? 'Start' : _plannedStart!),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _plannedStart == null
                    ? null
                    : () async {
                        final v = await _pickDateTime(
                          _plannedEnd ?? _plannedStart,
                        );
                        if (v == null) return;
                        setState(() => _plannedEnd = v);
                        _queueDraft();
                      },
                child: Text(_plannedEnd == null ? 'End' : _plannedEnd!),
              ),
            ),
            if (_plannedStart != null)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear interval',
                  onPressed: () {
                    setState(() {
                      _plannedStart = null;
                      _plannedEnd = null;
                    });
                    _queueDraft();
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _repeatSection(BuildContext context) {
    final dropdownValue = _customRrule
        ? '__custom__'
        : (_repeatPresets.containsValue(_rrule) ? _rrule : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: dropdownValue,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Repeat',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final e in _repeatPresets.entries)
              DropdownMenuItem(value: e.value, child: Text(e.key)),
          ],
          onChanged: (v) {
            if (v == '__custom__') {
              setState(() {
                _customRrule = true;
                if (_rrule == null && _rruleText.text.trim().isNotEmpty) {
                  _rrule = _rruleText.text.trim();
                }
              });
            } else {
              setState(() {
                _customRrule = false;
                _rrule = v;
              });
              _queueDraft();
            }
          },
        ),
        if (_customRrule) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _rruleText,
            decoration: InputDecoration(
              labelText: 'Custom RRULE',
              border: const OutlineInputBorder(),
              errorText: _rruleText.text.trim().isEmpty
                  ? null
                  : _validateRrule(_rruleText.text.trim()),
            ),
            onChanged: (t) {
              setState(() {
                final v = t.trim();
                _rrule = v.isEmpty ? null : v;
              });
              _queueDraft();
            },
          ),
        ],
      ],
    );
  }

  bool _isValidRrule(String value) {
    final body = value.trim().toUpperCase().startsWith('RRULE:')
        ? value.trim().substring(6)
        : value.trim();
    final freqPart = body
        .split(';')
        .where((p) => p.toUpperCase().startsWith('FREQ='))
        .firstOrNull;
    if (freqPart == null) return false;
    final freq = freqPart.split('=').last.toUpperCase();
    if (!const {'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'}.contains(freq)) {
      return false;
    }
    try {
      RecurrenceRule.parse(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  String? _validateRrule(String v) => _isValidRrule(v) ? null : 'Invalid RRULE';

  Widget _dueChip(BuildContext context, String label, String value) {
    final selected = _dueDate == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _dueDate = selected ? null : value);
        _queueDraft();
      },
    );
  }

  String _pad(int v) => v.toString().padLeft(2, '0');

  DateTime _nextWeekday(DateTime now, int weekday) {
    var d = DateTime(now.year, now.month, now.day + 1);
    while (d.weekday != weekday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }
}

class _SubtaskSection extends ConsumerWidget {
  const _SubtaskSection({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subsAsync = ref.watch(subtasksProvider(task.id));
    return subsAsync.maybeWhen(
      data: (subs) {
        final done = subs.where((s) => s.completedAt != null).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Subtasks $done/${subs.length}'),
            for (final s in subs)
              CheckboxListTile(
                value: s.completedAt != null,
                onChanged: (_) {
                  final repo = ref.read(taskRepositoryProvider);
                  if (s.completedAt != null) {
                    repo.uncompleteTask(s.id);
                  } else {
                    repo.completeTask(s.id);
                  }
                },
                title: Text(s.title),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            TextButton.icon(
              onPressed: () => showTaskEditor(context, parentId: task.id),
              icon: const Icon(Icons.add),
              label: const Text('Add subtask'),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

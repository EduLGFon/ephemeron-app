part of '../task_editor_sheet.dart';

mixin _TaskEditorSections on _TaskEditorStateBase {
  void _queueDraft();
  Widget _dateRow(
    BuildContext context, {
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
    required String pickerKey,
  });
  String _fmtDue(DateTime d);
  Future<String?> _pickDateTime(String? current, {required String pickerKey});
  bool get _isMicrosoftTask;
  Future<void> _save();
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
                              account: accountForSource(
                                googleAccount: list.googleAccount,
                                microsoftAccount: list.microsoftAccount,
                              ),
                              isLocal:
                                  list.googleAccount == null &&
                                  list.microsoftAccount == null,
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
                pickerKey: PickerMemoryKeys.taskPlannedDate,
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
                pickerKey: PickerMemoryKeys.taskDueDate,
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
                      SettingsRepository? settings;
                      try {
                        settings = await ref.read(
                          settingsRepositoryProvider.future,
                        );
                      } catch (_) {}
                      if (!context.mounted) return;
                      final minutes = resolvePickerTimeMinutes(
                        currentMinutes: _dueTime,
                        rememberedHhmm: settings?.getPickerTime(
                          PickerMemoryKeys.taskDueTime,
                        ),
                        fallbackMinutes: 540,
                      );
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: minutes ~/ 60,
                          minute: minutes % 60,
                        ),
                      );
                      if (t != null) {
                        final hhmm = formatHhmm(t.hour, t.minute);
                        try {
                          await settings?.setPickerTime(
                            PickerMemoryKeys.taskDueTime,
                            hhmm,
                          );
                        } catch (_) {}
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
                onPressed: (widget.task != null && _isMicrosoftTask)
                    ? null
                    : _save,
                child: Text(widget.task == null ? 'Create' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
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
                  final v = await _pickDateTime(
                    _plannedStart,
                    pickerKey: PickerMemoryKeys.taskPlannedStart,
                  );
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
                          pickerKey: PickerMemoryKeys.taskPlannedEnd,
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
        : (_TaskEditorStateBase._repeatPresets.containsValue(_rrule)
              ? _rrule
              : null);
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
            for (final e in _TaskEditorStateBase._repeatPresets.entries)
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

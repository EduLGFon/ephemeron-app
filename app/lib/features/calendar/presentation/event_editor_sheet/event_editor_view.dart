// Form build for the event editor, split from event_editor_state.dart.
part of '../event_editor_sheet.dart';

extension on _EventEditorState {
  Widget _buildEventEditor(BuildContext context) {
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

part of '../../event_editor_sheet.dart';

extension on _EventEditorState {
  Future<void> _pickDate(bool isStart) async {
    SettingsRepository? settings;
    try {
      settings = await ref.read(settingsRepositoryProvider.future);
    } catch (_) {}
    if (!mounted) return;
    final key = isStart
        ? PickerMemoryKeys.eventStart
        : PickerMemoryKeys.eventEnd;
    final d = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    _changed(() {
      if (isStart) {
        _start = DateTime(
          d.year,
          d.month,
          d.day,
          _allDay ? 0 : _start.hour,
          _allDay ? 0 : _start.minute,
        );
        if (_end.isBefore(_start)) {
          _end = _allDay ? _start : _start.add(const Duration(hours: 1));
        }
      } else {
        _end = DateTime(
          d.year,
          d.month,
          d.day,
          _allDay ? 0 : _end.hour,
          _allDay ? 0 : _end.minute,
        );
        if (_end.isBefore(_start)) {
          _end = _allDay ? _start : _start.add(const Duration(hours: 1));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('End was before start; adjusted.')),
          );
        }
      }
    });
    try {
      final dt = isStart ? _start : _end;
      await settings?.setPickerDateTime(key, dt.toIso8601String());
    } catch (_) {}
  }

  Future<void> _pickTime(bool isStart) async {
    SettingsRepository? settings;
    try {
      settings = await ref.read(settingsRepositoryProvider.future);
    } catch (_) {}
    if (!mounted) return;
    final key = isStart
        ? PickerMemoryKeys.eventStart
        : PickerMemoryKeys.eventEnd;
    final base = isStart ? _start : _end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
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
    try {
      final dt = isStart ? _start : _end;
      await settings?.setPickerDateTime(key, dt.toIso8601String());
    } catch (_) {}
  }
}

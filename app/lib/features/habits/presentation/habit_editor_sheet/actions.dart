part of '../habit_editor_sheet.dart';

mixin _HabitEditorSheetStateActions on _HabitEditorSheetStateBase {
  Map<String, dynamic> _snapshot() => {
    'name': _name.text,
    'amount': _amount.text,
    'unit': _unit.text,
    'step': _step.text,
    'sectionId': _sectionId,
    'frequency': _frequency,
    'weekdaysMask': _weekdaysMask,
    'weeklyTarget': _weeklyTarget,
    'intervalDays': _intervalDays,
    'startDate': _startDate,
    'reminderTime': _reminderTime,
    'alarmPreset': _alarmPreset,
  };

  void _queueDraft() => _saver?.changed(_snapshot);

  void _changed(void Function() fn) {
    setState(fn);
    _queueDraft();
  }

  Future<void> _addSection() async {
    final name = await _askText(context, 'New section', 'Name');
    if (name == null || name.trim().isEmpty) return;
    final repo = ref.read(habitRepositoryProvider);
    final id = await repo.createSection(name.trim());
    _changed(() => _sectionId = id);
  }

  Future<void> _pickStartDate() async {
    final initial = parseKey(_startDate);
    SettingsRepository? settings;
    try {
      settings = await ref.read(settingsRepositoryProvider.future);
    } catch (_) {}
    if (!mounted) return;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      final value = habitDateKey(d);
      try {
        await settings?.setPickerDate(PickerMemoryKeys.habitStartDate, value);
      } catch (_) {}
      _changed(() => _startDate = value);
    }
  }

  Future<void> _pickReminder() async {
    SettingsRepository? settings;
    try {
      settings = await ref.read(settingsRepositoryProvider.future);
    } catch (_) {}
    if (!mounted) return;
    final now = TimeOfDay.now();
    final minutes = resolvePickerTimeMinutes(
      currentMinutes: parseHhmm(_reminderTime),
      rememberedHhmm: settings?.getPickerTime(
        PickerMemoryKeys.habitReminderTime,
      ),
      fallbackMinutes: now.hour * 60 + now.minute,
    );
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (t == null) return;
    final hhmm = formatHhmm(t.hour, t.minute);
    try {
      await settings?.setPickerTime(PickerMemoryKeys.habitReminderTime, hhmm);
    } catch (_) {}
    _changed(() => _reminderTime = hhmm);
  }

  Future<void> _deleteHabit() async {
    final habit = widget.habit;
    if (habit == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete habit?'),
        content: const Text('This habit will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final pending = ref.read(pendingOperationsProvider);
    final opId = await pending.scheduleHabitDelete(habit.id);
    _saved = true;
    try {
      await ref.read(draftStoreProvider).clear('habit', _draftEntityId);
    } catch (_) {}
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Habit deleted.'),
        duration: const Duration(seconds: 6),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => pending.cancel(opId),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name is required.')));
      return;
    }
    final amount = double.tryParse(_amount.text.trim());
    // Moment of need, advisory only: the save always proceeds.
    if (_reminderTime != null || _alarmPreset != null) {
      final preset = AlarmPreset.tryParse(_alarmPreset);
      await AppPermissions.ensureAlarmPrereqs(
        context,
        exactAlarm: preset?.needsAlarmClock ?? false,
        fullScreen: preset?.usesFullScreen ?? false,
      );
      if (!mounted) return;
    }
    final repo = ref.read(habitRepositoryProvider);
    final existing = widget.habit;
    if (existing == null) {
      await repo.createHabit(
        name: name,
        sectionId: _sectionId,
        frequency: _frequency,
        weekdaysMask: _frequency == 'weekdays' ? _weekdaysMask : 0,
        weeklyTarget: _frequency == 'weekly' ? _weeklyTarget : null,
        intervalDays: _frequency == 'interval' ? _intervalDays : null,
        goalAmount: amount,
        unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
        increment: double.tryParse(_step.text.trim()) ?? 1,
        startDate: _startDate,
        reminderTime: _reminderTime,
        alarmPreset: _alarmPreset,
      );
    } else {
      await repo.updateHabit(
        existing.id,
        name: name,
        sectionId: () => _sectionId,
        frequency: _frequency,
        weekdaysMask: _frequency == 'weekdays' ? _weekdaysMask : 0,
        weeklyTarget: () => _frequency == 'weekly' ? _weeklyTarget : null,
        intervalDays: () => _frequency == 'interval' ? _intervalDays : null,
        goalAmount: () => amount,
        unit: () => _unit.text.trim().isEmpty ? null : _unit.text.trim(),
        increment: () => double.tryParse(_step.text.trim()) ?? 1,
        startDate: _startDate,
        reminderTime: () => _reminderTime,
        alarmPreset: () => _alarmPreset,
      );
    }
    _saved = true;
    try {
      await ref.read(draftStoreProvider).clear('habit', _draftEntityId);
      final srepo = await ref.read(settingsRepositoryProvider.future);
      final expected = widget.habit == null
          ? 'habit_new'
          : 'habit:${widget.habit!.id}';
      if (srepo.openSheet == expected) await srepo.setOpenSheet(null);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }
}

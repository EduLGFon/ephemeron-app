part of '../countdown_editor_sheet.dart';

extension _CountdownEditorActions on _CountdownEditorSheetState {
  Future<void> _pickDate() async {
    final now = DateTime.now();
    SettingsRepository? settings;
    try {
      settings = await ref.read(settingsRepositoryProvider.future);
    } catch (_) {}
    if (!mounted) return;
    final initial = resolvePickerDate(
      current: _date == null ? null : formatYmd(_date!),
      remembered: settings?.getPickerDate(PickerMemoryKeys.countdownTargetDate),
      fallback: now,
    );
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      try {
        await settings?.setPickerDate(
          PickerMemoryKeys.countdownTargetDate,
          formatYmd(d),
        );
      } catch (_) {}
      _changed(() => _date = d);
    }
  }

  Future<void> _pickAlertTime() async {
    SettingsRepository? settings;
    try {
      settings = await ref.read(settingsRepositoryProvider.future);
    } catch (_) {}
    if (!mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _alertHour, minute: _alertMinute),
    );
    if (t != null) {
      try {
        await settings?.setPickerTime(
          PickerMemoryKeys.countdownAlertTime,
          formatHhmm(t.hour, t.minute),
        );
      } catch (_) {}
      _changed(() {
        _alertHour = t.hour;
        _alertMinute = t.minute;
      });
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Title is required.')));
      return;
    }
    final targetDate = _date == null
        ? null
        : '${_date!.year.toString().padLeft(4, '0')}-'
              '${_date!.month.toString().padLeft(2, '0')}-'
              '${_date!.day.toString().padLeft(2, '0')}';
    // Countdown alerts always notify 3 days before and on the day, so the
    // notification prompt belongs to every save (advisory only).
    final preset = AlarmPreset.tryParse(_alarmPreset);
    await AppPermissions.ensureAlarmPrereqs(
      context,
      exactAlarm: preset?.needsAlarmClock ?? false,
      fullScreen: preset?.usesFullScreen ?? false,
    );
    if (!mounted) return;
    final repo = ref.read(countdownRepositoryProvider);
    final existing = widget.countdown;
    if (existing == null) {
      await repo.createCountdown(
        title: title,
        targetDate: targetDate,
        yearlyRepeat: _yearlyRepeat,
        showAge: _showAge,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        alertOffsetDays: _alertOffsetDays,
        alertTimeMin: _alertHour * 60 + _alertMinute,
        alarmPreset: _alarmPreset,
      );
    } else {
      await repo.updateCountdown(
        existing.id,
        title: title,
        targetDate: () => targetDate,
        yearlyRepeat: _yearlyRepeat,
        showAge: _showAge,
        notes: () => _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        alertOffsetDays: () => _alertOffsetDays,
        alertTimeMin: () => _alertHour * 60 + _alertMinute,
        alarmPreset: () => _alarmPreset,
      );
    }
    _saved = true;
    try {
      await ref.read(draftStoreProvider).clear('countdown', _draftEntityId);
      final srepo = await ref.read(settingsRepositoryProvider.future);
      final expected = widget.countdown == null
          ? 'countdown_new'
          : 'countdown:${widget.countdown!.id}';
      if (srepo.openSheet == expected) await srepo.setOpenSheet(null);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }
}

part of '../task_editor_sheet.dart';

mixin _TaskEditorPickers on _TaskEditorStateBase {
  // ignore: unused_element
  String _fmtDue(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ignore: unused_element
  Widget _dateRow(
    BuildContext context, {
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
    required String pickerKey,
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
            onPressed: () => _pickDate(value, onChanged, pickerKey: pickerKey),
          ),
          if (value != null)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear $label',
              onPressed: () => onChanged(null),
            ),
        ],
      ),
      onTap: () => _pickDate(value, onChanged, pickerKey: pickerKey),
    );
  }

  Future<void> _pickDate(
    String? current,
    ValueChanged<String?> onChanged, {
    required String pickerKey,
  }) async {
    final now = DateTime.now();
    SettingsRepository? settings;
    try {
      settings = await ref.read(settingsRepositoryProvider.future);
    } catch (_) {}
    if (!mounted) return;
    final initial = resolvePickerDate(
      current: current,
      remembered: settings?.getPickerDate(pickerKey),
      fallback: now,
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final value = formatYmd(picked);
      try {
        await settings?.setPickerDate(pickerKey, value);
      } catch (_) {}
      onChanged(value);
    }
  }

  // ignore: unused_element
  Future<String?> _pickDateTime(
    String? current, {
    required String pickerKey,
  }) async {
    final now = DateTime.now();
    SettingsRepository? settings;
    try {
      settings = await ref.read(settingsRepositoryProvider.future);
    } catch (_) {}
    if (!mounted) return null;
    final initial = resolvePickerDateTime(
      currentIso: current,
      rememberedIso: settings?.getPickerDateTime(pickerKey),
      fallback: now,
    );
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    final result = '${formatYmd(date)}T${formatHhmm(time.hour, time.minute)}';
    try {
      await settings?.setPickerDateTime(pickerKey, result);
    } catch (_) {}
    return result;
  }
}

// Habit editor bottom sheet: create and edit.
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session/session_restore.dart';
import '../../../data/drift/app_database.dart';
import '../../settings/application/settings_providers.dart';
import '../../../domain/alarms/alarm_preset.dart';
import '../../../domain/habits/date_key.dart';
import '../../../core/platform/app_permissions.dart';
import '../../../core/ui/escape_to_close.dart';
import '../../alarms/presentation/alarm_preset_picker.dart';
import '../application/habits_providers.dart';

Future<void> showHabitEditor(
  BuildContext context, {
  Habit? habit,
  Map<String, dynamic>? restoredDraft,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => EscapeToClose(
      child: _HabitEditorSheet(habit: habit, restoredDraft: restoredDraft),
    ),
  );
}

const _frequencies = ['daily', 'weekdays', 'weekly', 'interval'];

class _HabitEditorSheet extends ConsumerStatefulWidget {
  const _HabitEditorSheet({this.habit, this.restoredDraft});

  final Habit? habit;
  final Map<String, dynamic>? restoredDraft;

  @override
  ConsumerState<_HabitEditorSheet> createState() => _HabitEditorSheetState();
}

class _HabitEditorSheetState extends ConsumerState<_HabitEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _unit;
  String? _sectionId;
  String _frequency = 'daily';
  int _weekdaysMask = 127;
  int _weeklyTarget = 3;
  int _intervalDays = 2;
  late String _startDate;
  String? _reminderTime;
  String? _alarmPreset;
  DraftAutosaver? _saver;
  bool _saved = false;
  dynamic _settings;

  String get _draftEntityId => widget.habit?.id ?? 'new';

  Map<String, dynamic> _snapshot() => {
    'name': _name.text,
    'amount': _amount.text,
    'unit': _unit.text,
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

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    final d = widget.restoredDraft;
    _name = TextEditingController(
      text: (d?['name'] as String?) ?? h?.name ?? '',
    );
    _amount = TextEditingController(
      text:
          (d?['amount'] as String?) ??
          (h?.goalAmount != null ? '${h!.goalAmount}' : ''),
    );
    _unit = TextEditingController(
      text: (d?['unit'] as String?) ?? h?.unit ?? '',
    );
    _sectionId = (d?['sectionId'] as String?) ?? h?.sectionId;
    _frequency =
        (d?['frequency'] as String?) ??
        (_frequencies.contains(h?.frequency) ? h!.frequency : 'daily');
    _weekdaysMask =
        (d?['weekdaysMask'] as num?)?.toInt() ?? h?.weekdaysMask ?? 127;
    _weeklyTarget =
        (d?['weeklyTarget'] as num?)?.toInt() ?? h?.weeklyTarget ?? 3;
    _intervalDays =
        (d?['intervalDays'] as num?)?.toInt() ?? h?.intervalDays ?? 2;
    _startDate =
        (d?['startDate'] as String?) ??
        h?.startDate ??
        habitDateKey(DateTime.now());
    _reminderTime = (d?['reminderTime'] as String?) ?? h?.reminderTime;
    _alarmPreset = (d?['alarmPreset'] as String?) ?? h?.alarmPreset;
    for (final c in [_name, _amount, _unit]) {
      c.addListener(_queueDraft);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _saver ??= DraftAutosaver(
      ref.read(draftStoreProvider),
      'habit',
      _draftEntityId,
    );
    Future.microtask(() async {
      try {
        final repo = await ref.read(settingsRepositoryProvider.future);
        _settings = repo;
        await repo.setOpenSheet(
          widget.habit == null ? 'habit_new' : 'habit:${widget.habit!.id}',
        );
      } catch (_) {}
    });
  }

  String _expectedSheet() =>
      widget.habit == null ? 'habit_new' : 'habit:${widget.habit!.id}';

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
    _name.dispose();
    _amount.dispose();
    _unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sectionsAsync = ref.watch(habitSectionsProvider);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.habit == null ? 'New habit' : 'Edit habit',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: widget.habit == null,
            ),
            const SizedBox(height: 8),
            sectionsAsync.maybeWhen(
              data: (sections) => DropdownButtonFormField<String?>(
                initialValue: sections.any((s) => s.id == _sectionId)
                    ? _sectionId
                    : null,
                decoration: const InputDecoration(labelText: 'Section'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No section'),
                  ),
                  for (final s in sections)
                    DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => _changed(() => _sectionId = v),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
            TextButton(
              onPressed: _addSection,
              child: const Text('New section'),
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'daily', label: Text('Daily')),
                ButtonSegment(value: 'weekdays', label: Text('Days')),
                ButtonSegment(value: 'weekly', label: Text('Weekly')),
                ButtonSegment(value: 'interval', label: Text('Every N')),
              ],
              selected: {_frequency},
              onSelectionChanged: (s) => _changed(() => _frequency = s.single),
            ),
            const SizedBox(height: 8),
            if (_frequency == 'weekdays')
              _WeekdayPicker(
                mask: _weekdaysMask,
                onChanged: (m) => _changed(() => _weekdaysMask = m),
              ),
            if (_frequency == 'weekly')
              _Stepper(
                label: 'Days per week',
                value: _weeklyTarget,
                onChanged: (v) => _changed(() => _weeklyTarget = v),
              ),
            if (_frequency == 'interval')
              _Stepper(
                label: 'Every N days',
                value: _intervalDays,
                min: 2,
                onChanged: (v) => _changed(() => _intervalDays = v),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    decoration: const InputDecoration(
                      labelText: 'Goal amount (optional)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Start: ${DeviceDateFormat.dateIso(context, _startDate)}',
                  ),
                ),
                TextButton(
                  onPressed: _pickStartDate,
                  child: const Text('Change'),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: Text('Reminder: ${_reminderTime ?? 'none'}')),
                TextButton(onPressed: _pickReminder, child: const Text('Set')),
                if (_reminderTime != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => _changed(() => _reminderTime = null),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            AlarmPresetPicker(
              value: _alarmPreset,
              onChanged: (v) => _changed(() => _alarmPreset = v),
            ),
            const SizedBox(height: 4),
            const Text(
              'Reminder notifies daily. The alarm adds a stronger alert '
              'and is skipped when already done today.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
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
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) _changed(() => _startDate = habitDateKey(d));
  }

  Future<void> _pickReminder() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t == null) return;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    _changed(() => _reminderTime = '$hh:$mm');
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

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.mask, required this.onChanged});

  final int mask;
  final void Function(int mask) onChanged;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static List<String> _names(BuildContext context) => List.generate(
    7,
    (i) => DeviceDateFormat.eeee(context).format(DateTime(2024, 1, 1 + i)),
  );

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      children: [
        for (var i = 0; i < 7; i++)
          Semantics(
            label: _names(context)[i],
            selected: (mask & (1 << i)) != 0,
            child: FilterChip(
              label: Text(_labels[i]),
              selected: (mask & (1 << i)) != 0,
              onSelected: (_) => onChanged(mask ^ (1 << i)),
            ),
          ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
  });

  final String label;
  final int value;
  final void Function(int value) onChanged;
  final int min;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove),
          tooltip: 'Decrease $label',
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Text('$value'),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Increase $label',
          onPressed: () => onChanged(value + 1),
        ),
      ],
    );
  }
}

Future<String?> _askText(
  BuildContext context,
  String title,
  String label,
) async {
  // Not disposed: disposal would race the dialog pop transition, which
  // rebuilds the text field for a few frames after pop.
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

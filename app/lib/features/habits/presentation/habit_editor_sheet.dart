// Habit editor bottom sheet: create and edit.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../../domain/habits/date_key.dart';
import '../application/habits_providers.dart';

Future<void> showHabitEditor(BuildContext context, {Habit? habit}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HabitEditorSheet(habit: habit),
  );
}

const _frequencies = ['daily', 'weekdays', 'weekly', 'interval'];

class _HabitEditorSheet extends ConsumerStatefulWidget {
  const _HabitEditorSheet({this.habit});

  final Habit? habit;

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

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    _name = TextEditingController(text: h?.name ?? '');
    _amount = TextEditingController(
      text: h?.goalAmount != null ? '${h!.goalAmount}' : '',
    );
    _unit = TextEditingController(text: h?.unit ?? '');
    _sectionId = h?.sectionId;
    _frequency = _frequencies.contains(h?.frequency) ? h!.frequency : 'daily';
    _weekdaysMask = h?.weekdaysMask ?? 127;
    _weeklyTarget = h?.weeklyTarget ?? 3;
    _intervalDays = h?.intervalDays ?? 2;
    _startDate = h?.startDate ?? habitDateKey(DateTime.now());
    _reminderTime = h?.reminderTime;
  }

  @override
  void dispose() {
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
                onChanged: (v) => setState(() => _sectionId = v),
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
              onSelectionChanged: (s) => setState(() => _frequency = s.single),
            ),
            const SizedBox(height: 8),
            if (_frequency == 'weekdays')
              _WeekdayPicker(
                mask: _weekdaysMask,
                onChanged: (m) => setState(() => _weekdaysMask = m),
              ),
            if (_frequency == 'weekly')
              _Stepper(
                label: 'Days per week',
                value: _weeklyTarget,
                onChanged: (v) => setState(() => _weeklyTarget = v),
              ),
            if (_frequency == 'interval')
              _Stepper(
                label: 'Every N days',
                value: _intervalDays,
                min: 2,
                onChanged: (v) => setState(() => _intervalDays = v),
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
                Expanded(child: Text('Start: $_startDate')),
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
                    onPressed: () => setState(() => _reminderTime = null),
                  ),
              ],
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
    setState(() => _sectionId = id);
  }

  Future<void> _pickStartDate() async {
    final initial = parseKey(_startDate);
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _startDate = habitDateKey(d));
  }

  Future<void> _pickReminder() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t == null) return;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    setState(() => _reminderTime = '$hh:$mm');
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
      );
    }
    if (mounted) Navigator.of(context).pop();
  }
}

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.mask, required this.onChanged});

  final int mask;
  final void Function(int mask) onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Wrap(
      spacing: 4,
      children: [
        for (var i = 0; i < 7; i++)
          FilterChip(
            label: Text(labels[i]),
            selected: (mask & (1 << i)) != 0,
            onSelected: (_) => onChanged(mask ^ (1 << i)),
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
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Text('$value'),
        IconButton(
          icon: const Icon(Icons.add),
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

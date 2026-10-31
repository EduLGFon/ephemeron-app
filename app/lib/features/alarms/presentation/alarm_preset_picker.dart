// Shared alarm preset + reminder pickers used by event, task,
// countdown and habit editors.
import 'package:flutter/material.dart';

import '../../../domain/alarms/alarm_preset.dart';
import '../../../domain/alarms/reminder.dart';

class AlarmPresetPicker extends StatelessWidget {
  const AlarmPresetPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = AlarmPreset.tryParse(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: current?.id,
          decoration: const InputDecoration(
            labelText: 'Alarm',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem<String?>(value: null, child: Text('No alarm')),
            DropdownMenuItem<String?>(
              value: 'notification',
              child: Text('Notification - short sound'),
            ),
            DropdownMenuItem<String?>(
              value: 'full_short',
              child: Text('Full screen - short sound'),
            ),
            DropdownMenuItem<String?>(
              value: 'full_long',
              child: Text('Full screen - long sound + vibration'),
            ),
          ],
          onChanged: onChanged,
        ),
        if (current != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              current.description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class ReminderPicker extends StatelessWidget {
  const ReminderPicker({
    super.key,
    required this.offsets,
    required this.onChanged,
  });

  final List<int> offsets;
  final ValueChanged<List<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    final set = offsets.toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reminders (notifications)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final m in ReminderOptions.presets)
              FilterChip(
                label: Text(ReminderOptions.label(m)),
                selected: set.contains(m),
                onSelected: (_) {
                  final next = {...set};
                  if (next.contains(m)) {
                    next.remove(m);
                  } else {
                    next.add(m);
                  }
                  onChanged(next.toList()..sort());
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// Compact snooze selector used by the ring screen.
class SnoozePicker extends StatelessWidget {
  const SnoozePicker({super.key, required this.onPick});

  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final m in const [5, 10, 15, 30, 60])
          ActionChip(label: Text('${m}m'), onPressed: () => onPick(m)),
      ],
    );
  }
}

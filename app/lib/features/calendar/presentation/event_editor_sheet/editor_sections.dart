// Self-contained sections of the event editor form. Each takes its
// current value plus mutation callbacks so the editor state keeps the
// single source of truth.
part of '../event_editor_sheet.dart';

// All-day toggle plus start and end date/time rows.
class _EventWhenSection extends StatelessWidget {
  const _EventWhenSection({
    required this.allDay,
    required this.start,
    required this.end,
    required this.onToggleAllDay,
    required this.onPickDate,
    required this.onPickTime,
  });

  final bool allDay;
  final DateTime start;
  final DateTime end;
  final ValueChanged<bool> onToggleAllDay;
  final void Function(bool isStart) onPickDate;
  final void Function(bool isStart) onPickTime;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          value: allDay,
          onChanged: onToggleAllDay,
          title: const Text('All day'),
          contentPadding: EdgeInsets.zero,
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => onPickDate(true),
                child: Text(DeviceDateFormat.yMMMd(context).format(start)),
              ),
            ),
            const SizedBox(width: 8),
            if (!allDay)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onPickTime(true),
                  child: Text(_fmtTime(start)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => onPickDate(false),
                child: Text(DeviceDateFormat.yMMMd(context).format(end)),
              ),
            ),
            const SizedBox(width: 8),
            if (!allDay)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onPickTime(false),
                  child: Text(_fmtTime(end)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// Google Calendar color strip; null color uses the theme primary and
// shows a check on the selected swatch.
class _EventColorSection extends StatelessWidget {
  const _EventColorSection({required this.colorId, required this.onChanged});

  static const _colorIds = <String?>[
    null,
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    '11',
  ];

  final String? colorId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final c in _colorIds)
          GestureDetector(
            onTap: () => onChanged(c),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: c == null
                  ? Theme.of(context).colorScheme.primary
                  : googleCalendarColor(c),
              child: colorId == c
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }
}

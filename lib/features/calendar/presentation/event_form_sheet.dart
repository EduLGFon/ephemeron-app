import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../alarms/domain/reminder_offset.dart';
import '../application/calendar_providers.dart';
import '../domain/calendar_event.dart';

Future<void> showEventFormSheet(
  BuildContext context, {
  required DateTime initialDay,
  CalendarEvent? existingEvent,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => EventFormSheet(initialDay: initialDay, existingEvent: existingEvent),
  );
}

class EventFormSheet extends ConsumerStatefulWidget {
  const EventFormSheet({required this.initialDay, this.existingEvent, super.key});

  final DateTime initialDay;
  final CalendarEvent? existingEvent;

  @override
  ConsumerState<EventFormSheet> createState() => _EventFormSheetState();
}

class _EventFormSheetState extends ConsumerState<EventFormSheet> {
  late final _titleController = TextEditingController(text: widget.existingEvent?.title);
  late final _descriptionController =
      TextEditingController(text: widget.existingEvent?.description);
  late final _locationController = TextEditingController(text: widget.existingEvent?.location);

  late DateTime _start;
  late DateTime _end;
  late bool _isAllDay;
  String? _colorId;
  late Set<ReminderOffset> _selectedOffsets;
  bool _isSaving = false;

  bool get _isEditing => widget.existingEvent != null;

  @override
  void initState() {
    super.initState();
    final event = widget.existingEvent;
    _start = event?.start ?? DateTime(widget.initialDay.year, widget.initialDay.month,
        widget.initialDay.day, 9);
    _end = event?.end ?? _start.add(const Duration(hours: 1));
    _isAllDay = event?.isAllDay ?? false;
    _colorId = event?.colorId;
    _selectedOffsets = (event?.reminderMinutes ?? const [])
        .map(ReminderOffset.fromMinutes)
        .toSet();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isEditing ? 'Edit event' : 'New event', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              autofocus: !_isEditing,
              decoration: const InputDecoration(labelText: 'Title'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Location (optional)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('All day'),
              value: _isAllDay,
              onChanged: (value) => setState(() => _isAllDay = value),
            ),
            _DateTimeRow(
              label: 'Starts',
              value: _start,
              showTime: !_isAllDay,
              onChanged: (value) => setState(() {
                _start = value;
                if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
              }),
            ),
            _DateTimeRow(
              label: 'Ends',
              value: _end,
              showTime: !_isAllDay,
              onChanged: (value) => setState(() => _end = value),
            ),
            const SizedBox(height: 12),
            Text('Color', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final color in GoogleEventColor.options)
                  GestureDetector(
                    onTap: () => setState(() => _colorId = color.id),
                    child: CircleAvatar(
                      backgroundColor: Color(color.hex),
                      radius: 16,
                      child: _colorId == color.id
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Remind me', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final offset in ReminderOffset.presets)
                  FilterChip(
                    label: Text(offset.label),
                    selected: _selectedOffsets.contains(offset),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _selectedOffsets.add(offset);
                      } else {
                        _selectedOffsets.remove(offset);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving || _titleController.text.trim().isEmpty ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEditing ? 'Save' : 'Add event'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final repo = ref.read(calendarRepositoryProvider);
    final description = _descriptionController.text.trim();
    final location = _locationController.text.trim();

    final event = CalendarEvent(
      id: widget.existingEvent?.id ?? '',
      title: _titleController.text.trim(),
      description: description.isEmpty ? null : description,
      location: location.isEmpty ? null : location,
      start: _start,
      end: _end,
      isAllDay: _isAllDay,
      colorId: _colorId,
      reminderMinutes: _selectedOffsets.map((o) => o.beforeDue.inMinutes).toList(),
    );

    try {
      if (_isEditing) {
        await repo.updateEvent(event);
      } else {
        await repo.createEvent(event);
      }
      // Both the exact month(s) touched need a refetch — cheap to just
      // invalidate both start's and end's month in case an edit moved
      // an event across a month boundary.
      ref.invalidate(monthEventsProvider(DateTime(_start.year, _start.month, 1)));
      ref.invalidate(monthEventsProvider(DateTime(_end.year, _end.month, 1)));
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.label,
    required this.value,
    required this.showTime,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final bool showTime;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final dateLabel = '${value.year}-${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    final timeLabel = showTime
        ? ' ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}'
        : '';
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label)),
        Expanded(child: Text('$dateLabel$timeLabel')),
        TextButton(
          onPressed: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
            );
            if (date == null) return;

            if (!showTime) {
              onChanged(DateTime(date.year, date.month, date.day));
              return;
            }
            if (!context.mounted) return;
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(value),
            );
            onChanged(DateTime(
              date.year, date.month, date.day,
              time?.hour ?? value.hour, time?.minute ?? value.minute,
            ));
          },
          child: const Text('Change'),
        ),
      ],
    );
  }
}

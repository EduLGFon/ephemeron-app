// `show Value` only — importing the whole drift library also brings in
// its own `Column` class, which collides with Flutter's widget of the
// same name and fails to compile ("Column is imported from both...").
// Found during real-device testing.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../alarms/domain/alarm_preset.dart';
import '../../alarms/domain/reminder_offset.dart';
import '../application/task_providers.dart';
import '../domain/task_recurrence.dart';

/// Opens the add/edit sheet. Pass [existingTask] to edit, omit to create
/// a new task in [listId].
Future<void> showTaskFormSheet(
  BuildContext context, {
  required String listId,
  Task? existingTask,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        TaskFormSheet(listId: listId, existingTask: existingTask),
  );
}

class TaskFormSheet extends ConsumerStatefulWidget {
  const TaskFormSheet({required this.listId, this.existingTask, super.key});

  final String listId;
  final Task? existingTask;

  @override
  ConsumerState<TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends ConsumerState<TaskFormSheet> {
  late final _titleController = TextEditingController(
    text: widget.existingTask?.title,
  );
  late final _descriptionController = TextEditingController(
    text: widget.existingTask?.description,
  );

  late int _priority = widget.existingTask?.priority ?? 0;
  DateTime? _dueDate;
  bool _dueHasTime = false;
  AlarmPreset? _alarmPreset;
  late Set<ReminderOffset> _selectedOffsets = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final task = widget.existingTask;
    if (task != null) {
      _dueDate = task.dueDate;
      _dueHasTime = task.dueHasTime;
      _alarmPreset = task.alarmPreset != null
          ? AlarmPreset.values.byName(task.alarmPreset!)
          : null;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existingTask != null;

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
            Text(
              _isEditing ? 'Edit task' : 'New task',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              autofocus: !_isEditing,
              decoration: const InputDecoration(labelText: 'Title'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            _buildPriorityPicker(theme),
            const SizedBox(height: 16),
            _buildDuePicker(context, theme),
            if (_dueDate != null) ...[
              const SizedBox(height: 16),
              _buildAlarmPicker(theme),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving || _titleController.text.trim().isEmpty
                  ? null
                  : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditing ? 'Save' : 'Add task'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityPicker(ThemeData theme) {
    const labels = ['None', 'Low', 'Medium', 'High'];
    return Row(
      children: [
        Text('Priority', style: theme.textTheme.bodyMedium),
        const Spacer(),
        SegmentedButton<int>(
          segments: [
            for (var i = 0; i < labels.length; i++)
              ButtonSegment(value: i, label: Text(labels[i])),
          ],
          selected: {_priority},
          onSelectionChanged: (selection) =>
              setState(() => _priority = selection.first),
        ),
      ],
    );
  }

  Widget _buildDuePicker(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _dueDate == null
                ? 'No due date'
                : '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-'
                      '${_dueDate!.day.toString().padLeft(2, '0')}'
                      '${_dueHasTime ? ' ${_dueDate!.hour.toString().padLeft(2, '0')}:'
                                '${_dueDate!.minute.toString().padLeft(2, '0')}' : ''}',
            style: theme.textTheme.bodyLarge,
          ),
        ),
        TextButton(onPressed: _pickDate, child: const Text('Set date')),
        if (_dueDate != null)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
              _dueDate = null;
              _alarmPreset = null;
              _selectedOffsets = {};
            }),
          ),
      ],
    );
  }

  Widget _buildAlarmPicker(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Alarm', style: theme.textTheme.bodyMedium),
            const Spacer(),
            DropdownButton<AlarmPreset?>(
              value: _alarmPreset,
              hint: const Text('None'),
              items: const [
                DropdownMenuItem(value: null, child: Text('None')),
                DropdownMenuItem(
                  value: AlarmPreset.light,
                  child: Text('Light'),
                ),
                DropdownMenuItem(
                  value: AlarmPreset.medium,
                  child: Text('Medium'),
                ),
              ],
              onChanged: (value) => setState(() => _alarmPreset = value),
            ),
          ],
        ),
        if (_alarmPreset != null) ...[
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
        ],
      ],
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDate ?? now),
    );

    setState(() {
      _dueHasTime = time != null;
      _dueDate = time == null
          ? date
          : DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final repo = ref.read(taskRepositoryProvider);
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();

    try {
      if (_isEditing) {
        await repo.updateTask(
          widget.existingTask!.id,
          title: title,
          description: description.isEmpty ? null : description,
          priority: _priority,
          dueDate: Value(_dueDate),
          dueHasTime: _dueHasTime,
          alarmPreset: Value(_alarmPreset),
          reminderOffsets: _selectedOffsets.toList(),
        );
      } else {
        await repo.createTask(
          listId: widget.listId,
          title: title,
          description: description.isEmpty ? null : description,
          priority: _priority,
          dueDate: _dueDate,
          dueHasTime: _dueHasTime,
          recurrence: TaskRecurrence.none,
          alarmPreset: _alarmPreset,
          reminderOffsets: _selectedOffsets.toList(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

part of '../habit_editor_sheet.dart';

mixin _HabitEditorSheetStateView on _HabitEditorSheetStateWithActions {
  Widget _buildBody() {
    final context = this.context;
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
                  child: DropdownButtonFormField<String>(
                    initialValue: _unitPreset,
                    decoration: const InputDecoration(labelText: 'Unit preset'),
                    items: const [
                      DropdownMenuItem(value: 'count', child: Text('count')),
                      DropdownMenuItem(value: 'min', child: Text('min')),
                      DropdownMenuItem(value: 'custom', child: Text('custom')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      _changed(() {
                        _unitPreset = v;
                        if (v != 'custom') _unit.text = v;
                      });
                    },
                  ),
                ),
              ],
            ),
            if (_unitPreset == 'custom') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _unit,
                decoration: const InputDecoration(labelText: 'Custom unit'),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _step,
              decoration: const InputDecoration(
                labelText: 'Step / increment (default 1)',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
            if (widget.habit != null)
              OutlinedButton(
                onPressed: _deleteHabit,
                child: const Text('Delete habit'),
              ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}

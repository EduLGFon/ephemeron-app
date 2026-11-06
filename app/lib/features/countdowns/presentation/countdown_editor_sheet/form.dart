part of '../countdown_editor_sheet.dart';

extension _CountdownEditorForm on _CountdownEditorSheetState {
  Widget _buildForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.countdown == null ? 'New countdown' : 'Edit countdown',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title'),
          autofocus: widget.countdown == null,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _date == null
                    ? 'No date'
                    : DeviceDateFormat.yMMMd(context).format(_date!),
              ),
            ),
            TextButton(onPressed: _pickDate, child: const Text('Pick date')),
          ],
        ),
        SwitchListTile(
          title: const Text('Repeats yearly'),
          value: _yearlyRepeat,
          onChanged: (v) => _changed(() => _yearlyRepeat = v),
        ),
        SwitchListTile(
          title: const Text('Show age'),
          value: _showAge,
          onChanged: (v) => _changed(() => _showAge = v),
        ),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(labelText: 'Notes (optional)'),
          maxLines: 2,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Notify $_alertOffsetDays day(s) before + on the day at '
                '${_alertHour.toString().padLeft(2, '0')}:'
                '${_alertMinute.toString().padLeft(2, '0')}',
              ),
            ),
            TextButton(onPressed: _pickAlertTime, child: const Text('Time')),
          ],
        ),
        Row(
          children: [
            const Text('Days before:'),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _alertOffsetDays,
              items: const [
                DropdownMenuItem(value: 0, child: Text('On day only')),
                DropdownMenuItem(value: 1, child: Text('1 day')),
                DropdownMenuItem(value: 3, child: Text('3 days')),
                DropdownMenuItem(value: 7, child: Text('7 days')),
              ],
              onChanged: (v) => _changed(() => _alertOffsetDays = v ?? 3),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AlarmPresetPicker(
          value: _alarmPreset,
          onChanged: (v) => _changed(() => _alarmPreset = v),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

part of '../../task_editor_sheet.dart';

mixin _TaskEditorSectionsPlanned on _TaskEditorStateBase {
  void _queueDraft();
  Future<String?> _pickDateTime(String? current, {required String pickerKey});
  // ignore: unused_element
  Widget _plannedIntervalSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('Planned interval'),
          subtitle: Text(
            _plannedStart == null && _plannedEnd == null
                ? 'Not set'
                : '${_plannedStart ?? ''} - ${_plannedEnd ?? ''}',
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  final v = await _pickDateTime(
                    _plannedStart,
                    pickerKey: PickerMemoryKeys.taskPlannedStart,
                  );
                  if (v == null) return;
                  setState(() {
                    _plannedStart = v;
                    _plannedDate = null;
                    if (_plannedEnd != null) {
                      final s = DateTime.tryParse(v);
                      final e = DateTime.tryParse(_plannedEnd!);
                      if (s != null && e != null && !e.isAfter(s)) {
                        _plannedEnd = null;
                      }
                    }
                  });
                  _queueDraft();
                },
                child: Text(_plannedStart == null ? 'Start' : _plannedStart!),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _plannedStart == null
                    ? null
                    : () async {
                        final v = await _pickDateTime(
                          _plannedEnd ?? _plannedStart,
                          pickerKey: PickerMemoryKeys.taskPlannedEnd,
                        );
                        if (v == null) return;
                        setState(() => _plannedEnd = v);
                        _queueDraft();
                      },
                child: Text(_plannedEnd == null ? 'End' : _plannedEnd!),
              ),
            ),
            if (_plannedStart != null)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear interval',
                  onPressed: () {
                    setState(() {
                      _plannedStart = null;
                      _plannedEnd = null;
                    });
                    _queueDraft();
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }
}

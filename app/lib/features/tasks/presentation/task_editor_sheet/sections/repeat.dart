part of '../../task_editor_sheet.dart';

mixin _TaskEditorSectionsRepeat on _TaskEditorStateBase {
  void _queueDraft();
  // ignore: unused_element
  Widget _repeatSection(BuildContext context) {
    final dropdownValue = _customRrule
        ? '__custom__'
        : (_TaskEditorStateBase._repeatPresets.containsValue(_rrule)
              ? _rrule
              : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: dropdownValue,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Repeat',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final e in _TaskEditorStateBase._repeatPresets.entries)
              DropdownMenuItem(value: e.value, child: Text(e.key)),
          ],
          onChanged: (v) {
            if (v == '__custom__') {
              setState(() {
                _customRrule = true;
                if (_rrule == null && _rruleText.text.trim().isNotEmpty) {
                  _rrule = _rruleText.text.trim();
                }
              });
            } else {
              setState(() {
                _customRrule = false;
                _rrule = v;
              });
              _queueDraft();
            }
          },
        ),
        if (_customRrule) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _rruleText,
            decoration: InputDecoration(
              labelText: 'Custom RRULE',
              border: const OutlineInputBorder(),
              errorText: _rruleText.text.trim().isEmpty
                  ? null
                  : _validateRrule(_rruleText.text.trim()),
            ),
            onChanged: (t) {
              setState(() {
                final v = t.trim();
                _rrule = v.isEmpty ? null : v;
              });
              _queueDraft();
            },
          ),
        ],
      ],
    );
  }

  bool _isValidRrule(String value) {
    final body = value.trim().toUpperCase().startsWith('RRULE:')
        ? value.trim().substring(6)
        : value.trim();
    final freqPart = body
        .split(';')
        .where((p) => p.toUpperCase().startsWith('FREQ='))
        .firstOrNull;
    if (freqPart == null) return false;
    final freq = freqPart.split('=').last.toUpperCase();
    if (!const {'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'}.contains(freq)) {
      return false;
    }
    try {
      RecurrenceRule.parse(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  String? _validateRrule(String v) => _isValidRrule(v) ? null : 'Invalid RRULE';
}

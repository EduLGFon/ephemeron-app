part of '../../task_editor_sheet.dart';

mixin _TaskEditorSectionsDue on _TaskEditorStateBase {
  void _queueDraft();
  // ignore: unused_element
  Widget _dueChip(BuildContext context, String label, String value) {
    final selected = _dueDate == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _dueDate = selected ? null : value);
        _queueDraft();
      },
    );
  }

  // ignore: unused_element
  String _pad(int v) => v.toString().padLeft(2, '0');

  // ignore: unused_element
  DateTime _nextWeekday(DateTime now, int weekday) {
    var d = DateTime(now.year, now.month, now.day + 1);
    while (d.weekday != weekday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }
}

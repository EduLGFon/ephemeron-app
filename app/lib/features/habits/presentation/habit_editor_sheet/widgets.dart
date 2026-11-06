part of '../habit_editor_sheet.dart';

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.mask, required this.onChanged});

  final int mask;
  final void Function(int mask) onChanged;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static List<String> _names(BuildContext context) => List.generate(
    7,
    (i) => DeviceDateFormat.eeee(context).format(DateTime(2024, 1, 1 + i)),
  );

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      children: [
        for (var i = 0; i < 7; i++)
          Semantics(
            label: _names(context)[i],
            selected: (mask & (1 << i)) != 0,
            child: FilterChip(
              label: Text(_labels[i]),
              selected: (mask & (1 << i)) != 0,
              onSelected: (_) => onChanged(mask ^ (1 << i)),
            ),
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
          tooltip: 'Decrease $label',
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Text('$value'),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Increase $label',
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

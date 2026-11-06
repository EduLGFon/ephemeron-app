part of '../settings_widgets.dart';

class SettingsPickerTile<T> extends StatelessWidget {
  const SettingsPickerTile({
    super.key,
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
    this.help,
  });

  final String title;
  final String? help;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (help != null) ...[
            const SizedBox(height: 2),
            Text(help!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 6),
          DropdownButton<T>(
            value: value,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(12),
            items: items,
            onChanged: (next) {
              if (next != null) onChanged(next);
            },
          ),
        ],
      ),
    );
  }
}

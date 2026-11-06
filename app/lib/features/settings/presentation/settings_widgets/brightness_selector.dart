part of '../settings_widgets.dart';

class BrightnessSelector extends StatelessWidget {
  const BrightnessSelector({
    super.key,
    required this.title,
    required this.help,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String help;
  final AppBrightness value;
  final ValueChanged<AppBrightness> onChanged;

  static const _labels = <AppBrightness, String>{
    AppBrightness.light: 'Light',
    AppBrightness.dark: 'Dark',
    AppBrightness.amoled: 'AMOLED',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(help, style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final brightness in AppBrightness.values)
                ChoiceChip(
                  key: ValueKey('brightness-${brightness.name}'),
                  label: Text(_labels[brightness]!),
                  selected: value == brightness,
                  onSelected: (_) => onChanged(brightness),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

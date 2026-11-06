part of '../settings_widgets.dart';

class ColorPresetPicker extends StatelessWidget {
  const ColorPresetPicker({
    super.key,
    required this.title,
    required this.help,
    required this.presets,
    required this.selectedHex,
    required this.keyPrefix,
    required this.onSelected,
  });

  final String title;
  final String help;
  final List<Color> presets;

  /// Current color in `#RRGGBB` form; matching is alpha-insensitive.
  final String selectedHex;
  final String keyPrefix;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = isValidHex(selectedHex)
        ? colorToHex(parseHex(selectedHex))
        : null;
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
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final color in presets)
                _PresetSwatch(
                  color: color,
                  selected: normalized == colorToHex(color),
                  keyPrefix: keyPrefix,
                  onTap: onSelected,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({
    required this.color,
    required this.selected,
    required this.keyPrefix,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final String keyPrefix;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hex = colorToHex(color);
    final checkColor = color.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
    return Semantics(
      selected: selected,
      button: true,
      label: '$keyPrefix color $hex',
      child: Tooltip(
        message: hex,
        child: InkWell(
          key: ValueKey('$keyPrefix-color-$hex'),
          customBorder: const CircleBorder(),
          onTap: () => onTap(hex),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? Icon(
                    Icons.check,
                    key: ValueKey('$keyPrefix-selected-$hex'),
                    size: 20,
                    color: checkColor,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

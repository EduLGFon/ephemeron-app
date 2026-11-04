// Focused settings controls: section headers, dropdown rows, color presets,
// brightness chips, and custom hex fields. Keeping them separate keeps the
// settings screen focused on composition.
import 'package:flutter/material.dart';

import '../../../core/theme/theme_tokens.dart';

class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({
    super.key,
    required this.title,
    this.description,
  });

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Semantics(
        header: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: 2),
              Text(description!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

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

class HexColorFieldTile extends StatelessWidget {
  const HexColorFieldTile({
    super.key,
    required this.title,
    required this.help,
    required this.value,
    required this.fieldKey,
    required this.onSubmitted,
  });

  final String title;
  final String help;
  final String value;
  final Key fieldKey;
  final ValueChanged<String> onSubmitted;

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
          const SizedBox(height: 8),
          HexColorField(
            fieldKey: fieldKey,
            value: value,
            onSubmitted: onSubmitted,
          ),
        ],
      ),
    );
  }
}

class HexColorField extends StatefulWidget {
  const HexColorField({
    super.key,
    required this.value,
    required this.onSubmitted,
    this.fieldKey,
  });

  final String value;
  final ValueChanged<String> onSubmitted;
  final Key? fieldKey;

  @override
  State<HexColorField> createState() => _HexColorFieldState();
}

class _HexColorFieldState extends State<HexColorField> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(HexColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim();
    if (!isValidHex(raw)) {
      setState(() => _error = 'Enter a valid hex like #RRGGBB.');
      return;
    }
    setState(() => _error = null);
    final normalized = raw.startsWith('#') ? raw : '#$raw';
    _controller.text = normalized;
    widget.onSubmitted(normalized);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: _controller,
      autocorrect: false,
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        hintText: '#RRGGBB',
        errorText: _error,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (_) => _submit(),
    );
  }
}

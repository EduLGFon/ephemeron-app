part of '../settings_screen.dart';

List<Widget> _appearanceSection(
  _SettingsScreenState state,
  AppLocalizations l10n,
) {
  return [
    const SettingsSectionHeader(
      title: 'Appearance',
      description: 'Theme, colors and language.',
    ),
    BrightnessSelector(
      title: 'Brightness',
      help: 'Light, dark, or true-black AMOLED.',
      value: state._brightness,
      onChanged: state._setBrightness,
    ),
    ColorPresetPicker(
      title: 'Primary color',
      help: 'Accent for buttons, links and highlights.',
      presets: primaryPresets,
      selectedHex: state._primaryHex,
      keyPrefix: 'primary',
      onSelected: (hex) => state._selectColor(primary: true, hex: hex),
    ),
    HexColorFieldTile(
      title: 'Custom primary hex',
      help: 'Enter a valid value and press Enter.',
      value: state._primaryHex,
      fieldKey: const ValueKey('primary-hex-field'),
      onSubmitted: (hex) => state._selectColor(primary: true, hex: hex),
    ),
    ColorPresetPicker(
      title: 'Background color',
      help: 'Page background. Dark options pair with dark themes.',
      presets: backgroundPresets,
      selectedHex: state._backgroundHex,
      keyPrefix: 'background',
      onSelected: (hex) => state._selectColor(primary: false, hex: hex),
    ),
    HexColorFieldTile(
      title: 'Custom background hex',
      help: 'Enter a valid value and press Enter.',
      value: state._backgroundHex,
      fieldKey: const ValueKey('background-hex-field'),
      onSubmitted: (hex) => state._selectColor(primary: false, hex: hex),
    ),
    SettingsPickerTile<String>(
      title: l10n.languageTitle,
      help: 'System follows the device language.',
      value: state._localeCode,
      items: [
        DropdownMenuItem(value: 'system', child: Text(l10n.languageSystem)),
        DropdownMenuItem(value: 'en', child: Text(l10n.languageEnglish)),
        DropdownMenuItem(value: 'pt', child: Text(l10n.languagePortuguese)),
      ],
      onChanged: state._setLocale,
    ),
  ];
}

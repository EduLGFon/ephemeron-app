import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings/shared_preferences_provider.dart';
import 'theme_palettes.dart';

class ThemeEngineNotifier extends Notifier<AppPalette> {
  static const _primaryKey = 'theme.primaryColor';
  static const _backgroundKey = 'theme.backgroundColor';

  @override
  AppPalette build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final primaryValue = prefs.getInt(_primaryKey) ?? 0xFF6C63FF; // obsidian primary
    final backgroundValue = prefs.getInt(_backgroundKey) ?? 0xFF121212; // obsidian background
    
    return _buildPalette(Color(primaryValue), Color(backgroundValue));
  }

  Future<void> setPrimaryColor(Color color) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(_primaryKey, color.toARGB32());
    state = _buildPalette(color, state.background);
  }

  Future<void> setBackgroundColor(Color color) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(_backgroundKey, color.toARGB32());
    state = _buildPalette(state.primary, color);
  }

  AppPalette _buildPalette(Color primary, Color background) {
    final isLight = background.computeLuminance() > 0.5;
    return AppPalette(
      type: AppPaletteType.custom,
      name: 'Custom',
      primary: primary,
      secondary: const Color(0xFF03DAC6),
      background: background,
      surface: isLight ? Colors.white : const Color(0xFF1E1E1E),
      text: isLight ? Colors.black : const Color(0xFFE0E0E0),
      meshColors: [
        background,
        background,
        background,
        background,
      ],
      isAmoled: background == Colors.black,
    );
  }
}

final themeEngineProvider =
    NotifierProvider<ThemeEngineNotifier, AppPalette>(ThemeEngineNotifier.new);

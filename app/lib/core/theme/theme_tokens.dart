import 'package:flutter/material.dart';

// 10 primary color presets (user picks one or enters a custom hex).
const List<Color> primaryPresets = <Color>[
  Color(0xFF1E88E5), // Blue
  Color(0xFF00897B), // Teal
  Color(0xFF43A047), // Green
  Color(0xFFFDD835), // Amber
  Color(0xFFFB8C00), // Orange
  Color(0xFFE53935), // Red
  Color(0xFFD81B60), // Pink
  Color(0xFF8E24AA), // Purple
  Color(0xFF3949AB), // Indigo
  Color(0xFF546E7A), // Slate
];

// 6 background presets (user picks one or enters a custom hex).
const List<Color> backgroundPresets = <Color>[
  Color(0xFFFFFFFF), // White
  Color(0xFFFBF7F0), // Warm
  Color(0xFFF2F5FA), // Cool
  Color(0xFF121212), // Dark
  Color(0xFF0B0B0D), // Darker
  Color(0xFF000000), // AMOLED black
];

enum AppBrightness { light, dark, amoled }

Color parseHex(String hex) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

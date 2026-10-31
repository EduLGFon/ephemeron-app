import 'package:flutter/material.dart';

import 'theme_tokens.dart';

ThemeData buildTheme({
  required Color primary,
  required Color background,
  required AppBrightness brightness,
}) {
  final isDark = brightness != AppBrightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: isDark ? Brightness.dark : Brightness.light,
    surface: background,
  );
  final amoled = brightness == AppBrightness.amoled;
  final bg = amoled ? Colors.black : background;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(surface: bg),
    scaffoldBackgroundColor: bg,
    fontFamily: 'Inter',
    textTheme: const TextTheme().apply(fontFamily: 'Inter'),
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
}

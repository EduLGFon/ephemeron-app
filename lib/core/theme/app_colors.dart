import 'package:flutter/material.dart';

/// Ephemeron's palette, grounded in the app's own metaphor: small tasks
/// are ephemeral (dusk / passing time — petrol) and accumulate into
/// something larger (the hen filling her crop — harvest amber).
///
/// Deliberately not the generic "productivity blue/purple gradient", and
/// not the warm-cream-plus-terracotta combination either — accent here is
/// amber against petrol, not terracotta against cream.
abstract final class AppColors {
  // --- Light ---
  static const Color petrol = Color(0xFF1B4B4A);
  static const Color petrolDim = Color(0xFF3E6E6C);
  static const Color amber = Color(0xFFD89B3C);
  static const Color amberDim = Color(0xFFEBC888);
  static const Color surfaceLight = Color(0xFFFAF7F2);
  static const Color surfaceContainerLight = Color(0xFFF0ECE3);
  static const Color textLight = Color(0xFF262322);
  static const Color errorLight = Color(0xFFB3452F);

  // --- Dark ---
  static const Color surfaceDark = Color(0xFF10201F);
  static const Color surfaceContainerDark = Color(0xFF17302E);
  static const Color textDark = Color(0xFFEDE9E2);
  static const Color errorDark = Color(0xFFE0876D);

  // --- Priority flags (used across Tasks, Matrix) ---
  static const Color priorityHigh = Color(0xFFB3452F);
  static const Color priorityMedium = Color(0xFFD89B3C);
  static const Color priorityLow = Color(0xFF3E6E6C);
  static const Color priorityNone = Color(0xFF9A958C);
}

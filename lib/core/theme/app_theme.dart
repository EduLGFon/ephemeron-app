import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Builds the app's [ThemeData] for light and dark modes.
///
/// Type pairing is deliberate, not a Material default: Fraunces (warm,
/// slightly organic serif) carries section headers, dates, and countdown
/// numbers — the moments that should feel human. Inter carries the dense,
/// daily-use UI (lists, task rows) where legibility matters more than
/// character.
class AppTheme {
  const AppTheme._();

  static ThemeData light({required bool reducedMotion}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.petrol,
      brightness: Brightness.light,
      primary: AppColors.petrol,
      secondary: AppColors.amber,
      surface: AppColors.surfaceLight,
      error: AppColors.errorLight,
    );
    return _build(colorScheme, reducedMotion: reducedMotion);
  }

  static ThemeData dark({required bool reducedMotion}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.petrolDim,
      brightness: Brightness.dark,
      primary: AppColors.amberDim,
      secondary: AppColors.petrolDim,
      surface: AppColors.surfaceDark,
      error: AppColors.errorDark,
    );
    return _build(colorScheme, reducedMotion: reducedMotion);
  }

  static ThemeData _build(
    ColorScheme colorScheme, {
    required bool reducedMotion,
  }) {
    final textTheme = _textTheme(colorScheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,
      // Power-saving mode / user preference collapses page transitions to
      // an instant fade instead of the full slide+fade — this is the hook
      // the rest of the app's animations should check against too.
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: reducedMotion
                ? const FadeUpwardsPageTransitionsBuilder()
                : const _EphemeronPageTransitionsBuilder(),
        },
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondary.withValues(alpha: 0.25),
        labelTextStyle: WidgetStateProperty.all(
          textTheme.labelSmall,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.secondary,
        foregroundColor: colorScheme.onSecondary,
      ),
    );
  }

  static TextTheme _textTheme(Color onSurface) {
    const display = 'Fraunces';
    const body = 'Inter';
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: display,
        fontWeight: FontWeight.w600,
        fontSize: 40,
        color: onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: display,
        fontWeight: FontWeight.w600,
        fontSize: 26,
        color: onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: display,
        fontWeight: FontWeight.w600,
        fontSize: 20,
        color: onSurface,
      ),
      bodyLarge: TextStyle(fontFamily: body, fontSize: 16, color: onSurface),
      bodyMedium: TextStyle(fontFamily: body, fontSize: 14, color: onSurface),
      labelSmall: TextStyle(
        fontFamily: body,
        fontWeight: FontWeight.w500,
        fontSize: 12,
        color: onSurface,
      ),
    );
  }
}

/// A restrained custom transition (subtle fade + slight rise) used only
/// when the user has not requested reduced motion.
class _EphemeronPageTransitionsBuilder extends PageTransitionsBuilder {
  const _EphemeronPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings/app_settings_provider.dart';

class AppLoadingIndicator extends ConsumerStatefulWidget {
  final double size;

  const AppLoadingIndicator({
    super.key,
    this.size = 64.0,
  });

  @override
  ConsumerState<AppLoadingIndicator> createState() =>
      _AppLoadingIndicatorState();
}

class _AppLoadingIndicatorState extends ConsumerState<AppLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final imageAsset =
        isDark ? 'assets/app_icon_inverted.png' : 'assets/app_icon.png';
    final shouldReduceMotion =
        ref.watch(appSettingsProvider).shouldReduceMotion;

    final image = Image.asset(
      imageAsset,
      width: widget.size,
      height: widget.size,
    );

    if (shouldReduceMotion) return image;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: image,
    );
  }
}

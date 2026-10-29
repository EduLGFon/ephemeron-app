import 'package:flutter/material.dart';

/// A lightweight wrapper that applies bottom padding corresponding to [MediaQuery.viewInsetsOf(context).bottom]
/// without rebuilding its [child] subtree when the soft keyboard animates open/closed.
class KeyboardAvoidPadding extends StatelessWidget {
  const KeyboardAvoidPadding({
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: padding.copyWith(
        bottom: padding.bottom + bottomInset,
      ),
      child: child,
    );
  }
}

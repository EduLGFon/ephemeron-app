// Wraps a widget so pressing Escape pops the nearest navigator route.
// Used by modal bottom sheets to close on Esc.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EscapeToClose extends StatelessWidget {
  const EscapeToClose({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!context.mounted) return;
          final nav = Navigator.of(context);
          if (nav.canPop()) nav.pop();
        },
      },
      child: child,
    );
  }
}
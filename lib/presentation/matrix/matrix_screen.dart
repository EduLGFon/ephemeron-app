import 'package:flutter/material.dart';

/// Placeholder for the Eisenhower Matrix section — real content arrives in its own
/// build step. Exists now purely so the shell has something to navigate
/// to and StatefulShellRoute has a branch to preserve state for.
class MatrixScreen extends StatelessWidget {
  const MatrixScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Eisenhower Matrix')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_view_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('Eisenhower Matrix', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Coming in a later build step',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

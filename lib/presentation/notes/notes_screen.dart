import 'package:flutter/material.dart';

/// Placeholder for the Notes section — real content arrives in its own
/// build step. Exists now purely so the shell has something to navigate
/// to and StatefulShellRoute has a branch to preserve state for.
class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notes_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('Notes', style: theme.textTheme.titleLarge),
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

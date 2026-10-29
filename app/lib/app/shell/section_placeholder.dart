import 'package:flutter/material.dart';

import 'app_sections.dart';

class SectionPlaceholder extends StatelessWidget {
  const SectionPlaceholder({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final section = AppSection.values[index];
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              section.icon,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(section.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Nothing here yet',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

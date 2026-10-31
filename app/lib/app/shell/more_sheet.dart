import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_sections.dart';

class MoreSheet extends StatelessWidget {
  const MoreSheet({
    super.key,
    required this.more,
    required this.onSelected,
    required this.onReorder,
  });

  final List<int> more;
  final ValueChanged<int> onSelected;
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final idx in more)
            ListTile(
              leading: Icon(AppSection.values[idx].icon),
              title: Text(AppSection.values[idx].title),
              onTap: () => onSelected(idx),
            ),
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Search'),
            onTap: () {
              Navigator.of(context).pop();
              context.push('/search');
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () {
              Navigator.of(context).pop();
              context.push('/settings');
            },
          ),
          ListTile(
            leading: const Icon(Icons.reorder),
            title: const Text('Customize navigation'),
            onTap: onReorder,
          ),
        ],
      ),
    );
  }
}

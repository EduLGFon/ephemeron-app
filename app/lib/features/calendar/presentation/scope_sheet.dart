// Scope sheet for recurring edits/deletes: this / following / all.
import 'package:flutter/material.dart';

import '../../../data/repositories/event_repository.dart';

Future<EditScope?> showScopeSheet(
  BuildContext context, {
  bool allowSingle = true,
}) {
  return showModalBottomSheet<EditScope>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Which events?'),
          ),
          if (allowSingle)
            ListTile(
              title: const Text('This event'),
              onTap: () => Navigator.of(ctx).pop(EditScope.single),
            ),
          ListTile(
            title: const Text('This and following events'),
            onTap: () => Navigator.of(ctx).pop(EditScope.following),
          ),
          ListTile(
            title: const Text('All events'),
            onTap: () => Navigator.of(ctx).pop(EditScope.all),
          ),
        ],
      ),
    ),
  );
}

import 'package:flutter/material.dart';

import '../domain/countdown_type.dart';
import 'countdown_form_sheet.dart';

Future<void> showCountdownTemplatePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final type in CountdownType.values)
            ListTile(
              leading: Icon(_iconFor(type)),
              title: Text(type.label),
              onTap: () {
                Navigator.pop(context);
                showCountdownFormSheet(context, type: type);
              },
            ),
        ],
      ),
    ),
  );
}

IconData _iconFor(CountdownType type) {
  return switch (type) {
    CountdownType.holiday => Icons.celebration_outlined,
    CountdownType.anniversary => Icons.favorite_outline,
    CountdownType.birthday => Icons.cake_outlined,
    CountdownType.custom => Icons.hourglass_bottom_outlined,
  };
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme_engine_provider.dart';

enum RecurrenceDeleteType {
  onlyThis,
  thisAndAllAfter,
  all,
}

Future<RecurrenceDeleteType?> showRecurrenceDeleteDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String title,
}) async {
  final palette = ref.read(themeEngineProvider);

  return showDialog<RecurrenceDeleteType>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.text.withValues(alpha: 0.1)),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: palette.text,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              title: Text('Delete only this occurrence', style: TextStyle(color: palette.text)),
              onTap: () => Navigator.of(context).pop(RecurrenceDeleteType.onlyThis),
            ),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              title: Text('Delete this and all after', style: TextStyle(color: palette.text)),
              onTap: () => Navigator.of(context).pop(RecurrenceDeleteType.thisAndAllAfter),
            ),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              title: Text('Delete all events in series', style: TextStyle(color: palette.text)),
              onTap: () => Navigator.of(context).pop(RecurrenceDeleteType.all),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(
              'Cancel',
              style: TextStyle(color: palette.text.withValues(alpha: 0.6)),
            ),
          ),
        ],
      );
    },
  );
}

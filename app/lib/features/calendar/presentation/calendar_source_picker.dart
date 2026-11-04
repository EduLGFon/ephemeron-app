// Calendar source picker: account first, then a writable calendar.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/source_picker_sheet.dart';
import '../../../data/drift/app_database.dart';
import '../../../domain/sources/source_move.dart';
import '../../tasks/application/tasks_providers.dart';
import '../application/calendar_providers.dart';

List<SourceOption> calendarSourceOptions(List<Calendar> calendars) {
  return [
    for (final calendar in calendars)
      SourceOption(
        id: calendar.id,
        name: calendar.name,
        account: calendar.googleAccount ?? 'Google',
        isLocal: calendar.source != 'google',
        enabled: !calendar.readOnly,
      ),
  ];
}

Future<String?> showCalendarSourcePicker(
  BuildContext context,
  WidgetRef ref, {
  String? selectedId,
}) {
  final calendars = ref.read(calendarsProvider).value ?? const <Calendar>[];
  return showSourcePickerSheet(
    context,
    title: 'Calendar source',
    options: calendarSourceOptions(calendars),
    selectedId: selectedId,
  );
}

/// Returns true when the event moved to a different calendar.
Future<bool> pickAndMoveEvent(
  BuildContext context,
  WidgetRef ref, {
  required String eventId,
  required String currentCalendarId,
}) async {
  final target = await showCalendarSourcePicker(
    context,
    ref,
    selectedId: currentCalendarId,
  );
  if (target == null || target == currentCalendarId || !context.mounted) {
    return false;
  }
  try {
    await ref
        .read(eventRepositoryProvider)
        .moveEventToCalendar(eventId, target);
    ref.read(occurrenceDirtyProvider.notifier).markDirty();
    ref.invalidate(occurrenceSourceMapProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Event moved.')));
    }
    return true;
  } on SourceMoveException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
    return false;
  }
}

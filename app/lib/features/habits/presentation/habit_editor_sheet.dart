// Habit editor bottom sheet: create and edit.
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session/session_restore.dart';
import '../../../core/platform/app_permissions.dart';
import '../../../core/time/picker_memory.dart';
import '../../../core/ui/app_sheet.dart';
import '../../../core/ui/escape_to_close.dart';
import '../../../data/drift/app_database.dart';
import '../../../domain/alarms/alarm_preset.dart';
import '../../../domain/habits/date_key.dart';
import '../../alarms/presentation/alarm_preset_picker.dart';
import '../../settings/application/settings_providers.dart';
import '../../settings/data/settings_repository.dart';
import '../../sync/application/pending_operations.dart';
import '../application/habits_providers.dart';

part 'habit_editor_sheet/state.dart';
part 'habit_editor_sheet/actions.dart';
part 'habit_editor_sheet/view.dart';
part 'habit_editor_sheet/widgets.dart';

Future<void> showHabitEditor(
  BuildContext context, {
  Habit? habit,
  Map<String, dynamic>? restoredDraft,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => EscapeToClose(
      child: _HabitEditorSheet(habit: habit, restoredDraft: restoredDraft),
    ),
  );
}

const _frequencies = ['daily', 'weekdays', 'weekly', 'interval'];

class _HabitEditorSheet extends ConsumerStatefulWidget {
  const _HabitEditorSheet({this.habit, this.restoredDraft});

  final Habit? habit;
  final Map<String, dynamic>? restoredDraft;

  @override
  ConsumerState<_HabitEditorSheet> createState() => _HabitEditorSheetState();
}

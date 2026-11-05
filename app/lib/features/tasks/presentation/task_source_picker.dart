// Task list source picker: account first, then one of its lists.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/source_picker_sheet.dart';
import '../../../domain/sources/source_label.dart';
import '../../../data/drift/app_database.dart';
import '../../../domain/sources/source_move.dart';
import '../../calendar/application/calendar_providers.dart';
import '../application/tasks_providers.dart';

List<SourceOption> taskListSourceOptions(List<TaskList> lists) {
  return [
    for (final list in lists)
      SourceOption(
        id: list.id,
        name: list.name,
        account:
            accountForSource(
              googleAccount: list.googleAccount,
              microsoftAccount: list.microsoftAccount,
            ) ??
            (list.remoteId == null ? null : 'Microsoft'),
        isLocal:
            list.googleAccount == null &&
            list.microsoftAccount == null &&
            list.remoteId == null,
        enabled: list.deletedAt == null,
      ),
  ];
}

Future<String?> showTaskListSourcePicker(
  BuildContext context,
  WidgetRef ref, {
  String? selectedId,
}) {
  final lists = ref.read(taskListsProvider).value ?? const <TaskList>[];
  return showSourcePickerSheet(
    context,
    title: 'List source',
    options: taskListSourceOptions(lists),
    selectedId: selectedId,
  );
}

/// Returns true when the task moved to a different list.
Future<bool> pickAndMoveTask(
  BuildContext context,
  WidgetRef ref, {
  required String taskId,
  required String? currentListId,
}) async {
  final target = await showTaskListSourcePicker(
    context,
    ref,
    selectedId: currentListId,
  );
  if (target == null || target == currentListId || !context.mounted) {
    return false;
  }
  try {
    await ref.read(taskRepositoryProvider).moveTasks([taskId], target);
    ref.read(occurrenceDirtyProvider.notifier).markDirty();
    ref.invalidate(occurrenceSourceMapProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Task moved.')));
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

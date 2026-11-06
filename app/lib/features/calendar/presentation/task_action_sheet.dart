import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/device_date_format.dart';
import '../../../core/ui/app_sheet.dart';
import '../../../core/ui/escape_to_close.dart';
import '../../../core/db/db_provider.dart';
import '../../../data/drift/app_database.dart';
import '../../../domain/sources/microsoft_source.dart';
import '../../tasks/application/tasks_providers.dart';
import '../../tasks/presentation/task_editor_sheet.dart';

part 'task_action_sheet/sheet.dart';

Future<void> showTaskActionSheet(
  BuildContext context, {
  required String taskId,
  required String occurrenceDate,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => EscapeToClose(
      child: TaskActionSheet(taskId: taskId, occurrenceDate: occurrenceDate),
    ),
  );
}

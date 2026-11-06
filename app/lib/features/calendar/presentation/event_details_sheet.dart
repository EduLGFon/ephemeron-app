// Event details sheet: view, edit, delete with scope, duplicate.
//
// The sheet implementation is split across `part` files under
// `event_details_sheet/` while this file stays the public entry point.
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/system_launcher.dart';
import '../../../core/ui/app_sheet.dart';
import '../../../core/ui/escape_to_close.dart';
import '../../../data/drift/app_database.dart';
import '../../../core/db/db_provider.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../domain/sources/microsoft_source.dart';
import '../../../domain/sources/source_label.dart';
import '../../auth/application/auth_providers.dart';
import '../../notes/application/notes_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../sync/application/pending_operations.dart';
import '../../tasks/application/tasks_providers.dart';
import '../../notes/presentation/note_editor_screen.dart';
import '../../tasks/presentation/task_editor_sheet.dart';
import '../../tasks/presentation/task_source_picker.dart';
import '../application/calendar_providers.dart';
import 'calendar_source_picker.dart';
import 'event_editor_sheet.dart';
import 'scope_sheet.dart';

part 'event_details_sheet/details_actions.dart';
part 'event_details_sheet/details_sheet.dart';
part 'event_details_sheet/details_widgets.dart';
part 'event_details_sheet/event_details_body.dart';
part 'event_details_sheet/task_details_body.dart';

Future<void> showEventDetails(BuildContext context, String eventId) async {
  // Track the open modal so a kill while viewing restores it.
  // Normal close clears the marker below; process kill skips it.
  try {
    final container = ProviderScope.containerOf(context);
    final repo = await container.read(settingsRepositoryProvider.future);
    await repo.setOpenSheet('event_details:$eventId');
  } catch (_) {}
  if (!context.mounted) return;
  try {
    await showAppSheet<void>(
      context,
      builder: (_) => EscapeToClose(child: _Details(eventId: eventId)),
    );
  } finally {
    try {
      if (context.mounted) {
        final container = ProviderScope.containerOf(context);
        final repo = await container.read(settingsRepositoryProvider.future);
        if (repo.openSheet == 'event_details:$eventId') {
          await repo.setOpenSheet(null);
        }
      }
    } catch (_) {}
  }
}

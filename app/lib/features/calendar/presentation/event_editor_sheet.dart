// Event editor: title, calendar, all-day/timed, timezone note,
// repeat presets, location, notes. Recurring edits ask scope.
// Unsaved input autosaves (debounced) and restores after restart.
//
// Implementation lives in part files under event_editor_sheet/:
// helpers (formatting/rule summaries), the custom repeat dialog,
// self-contained form sections, and the editor state. The public
// entry point stays in this file so importer paths are unchanged.
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:ephemeron/core/ui/app_sheet.dart';
import 'package:ephemeron/core/ui/sheet_padding.dart';
import 'package:ephemeron/core/ui/escape_to_close.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session/session_restore.dart';
import '../../../core/platform/app_permissions.dart';
import '../../../core/time/picker_memory.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../domain/alarms/alarm_preset.dart';
import '../../../domain/alarms/reminder.dart';
import '../../../domain/recurrence/recurrence_rule.dart';
import '../../../domain/sources/microsoft_source.dart';
import '../../../domain/sources/source_label.dart';
import '../../../domain/sources/source_move.dart';
import '../../alarms/presentation/alarm_preset_picker.dart';
import '../../notes/application/notes_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../settings/data/settings_repository.dart';
import '../application/calendar_providers.dart';
import 'calendar_source_picker.dart';
import 'google_calendar_colors.dart';
import 'scope_sheet.dart';

part 'event_editor_sheet/editor_helpers.dart';
part 'event_editor_sheet/custom_repeat_dialog.dart';
part 'event_editor_sheet/editor_sections.dart';
part 'event_editor_sheet/event_editor_state.dart';
part 'event_editor_sheet/event_editor_draft.dart';
part 'event_editor_sheet/event_editor_view.dart';
part 'event_editor_sheet/event_editor_save.dart';

Future<void> showEventEditor(
  BuildContext context, {
  Event? event,
  DateTime? initialDay,
  int? initialHour,
  Map<String, dynamic>? restoredDraft,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => EscapeToClose(
      child: _EventEditor(
        event: event,
        initialDay: initialDay,
        initialHour: initialHour,
        restoredDraft: restoredDraft,
      ),
    ),
  );
}

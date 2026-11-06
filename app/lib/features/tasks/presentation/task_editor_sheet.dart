// Task create/edit sheet with list, priority, due chips, tags, subtasks.
// Unsaved input autosaves (debounced) and restores after restart.
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
import '../../../domain/alarms/alarm_preset.dart';
import '../../../domain/alarms/reminder.dart';
import '../../../domain/recurrence/recurrence_rule.dart';
import '../../../domain/sources/microsoft_source.dart';
import '../../../domain/sources/source_label.dart';
import '../../../domain/sources/source_move.dart';
import '../../alarms/presentation/alarm_preset_picker.dart';
import '../../settings/application/settings_providers.dart';
import '../../settings/data/settings_repository.dart';
import '../application/tasks_providers.dart';
import 'task_source_picker.dart';

part 'task_editor_sheet/lifecycle.dart';
part 'task_editor_sheet/save.dart';
part 'task_editor_sheet/pickers.dart';
part 'task_editor_sheet/sections.dart';
part 'task_editor_sheet/sections/planned.dart';
part 'task_editor_sheet/sections/repeat.dart';
part 'task_editor_sheet/sections/due.dart';
part 'task_editor_sheet/subtasks.dart';

Future<void> showTaskEditor(
  BuildContext context, {
  Task? task,
  String? parentId,
  Map<String, dynamic>? restoredDraft,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => EscapeToClose(
      child: _TaskEditor(
        task: task,
        parentId: parentId,
        restoredDraft: restoredDraft,
      ),
    ),
  );
}

class _TaskEditor extends ConsumerStatefulWidget {
  const _TaskEditor({this.task, this.parentId, this.restoredDraft});

  final Task? task;
  final String? parentId;
  final Map<String, dynamic>? restoredDraft;

  @override
  ConsumerState<_TaskEditor> createState() => _TaskEditorState();
}

abstract class _TaskEditorStateBase extends ConsumerState<_TaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _tags;
  String? _listId;
  int _priority = 0;
  String? _dueDate;
  String? _plannedDate;
  String? _plannedStart;
  String? _plannedEnd;
  String? _rrule;
  final TextEditingController _rruleText = TextEditingController();
  int? _dueTime;
  bool _pinned = false;
  String? _alarmPreset;
  bool _customRrule = false;
  static const Map<String, String?> _repeatPresets = {
    'Does not repeat': null,
    'Daily': 'FREQ=DAILY',
    'Weekly': 'FREQ=WEEKLY',
    'Monthly': 'FREQ=MONTHLY',
    'Yearly': 'FREQ=YEARLY',
    'Custom RRULE': '__custom__',
  };
  List<int> _reminders = const [0];
  DraftAutosaver? _saver;
  bool _saved = false;
  SettingsRepository? _settings;
}

class _TaskEditorState extends _TaskEditorStateBase
    with
        _TaskEditorLifecycle,
        _TaskEditorSave,
        _TaskEditorPickers,
        _TaskEditorSections,
        _TaskEditorSectionsPlanned,
        _TaskEditorSectionsRepeat,
        _TaskEditorSectionsDue {}

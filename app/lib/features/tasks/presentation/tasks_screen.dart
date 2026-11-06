// Tasks screen: list filter, overdue section, swipe actions with undo,
// trash, completed view, quick add FAB.
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';

import 'package:ephemeron/core/ui/empty_state.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../../domain/sources/source_label.dart';
import '../../../domain/sources/microsoft_source.dart';
import '../../../domain/tasks/task_sort.dart';
import '../../settings/application/settings_providers.dart';
import '../../sync/application/pending_operations.dart';
import '../../sync/presentation/sync_title.dart';
import '../application/task_sorting.dart';
import '../application/tasks_providers.dart';
import 'quick_add_sheet.dart';
import 'smart_list_editor_sheet.dart';
import 'smart_lists_screen.dart';
import 'task_editor_sheet.dart';
import 'task_list_dialogs.dart';
import 'task_lists_screen.dart';
import 'task_source_picker.dart';
import 'trash_screen.dart';

part 'tasks_screen/tasks_screen_view.dart';
part 'tasks_screen/custom_task_list.dart';
part 'tasks_screen/task_tile.dart';
part 'tasks_screen/move_buttons.dart';
part 'tasks_screen/error_state.dart';
part 'tasks_screen/completed_screen.dart';

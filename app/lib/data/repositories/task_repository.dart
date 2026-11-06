// Task, list, tag and smart-list repository. Drift/local only.
// Every mutation writes optimistically and enqueues an outbox row;
// the user never waits on the network.
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/search/sanitize.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/outbox_helper.dart';
import 'package:ephemeron/data/repositories/pending_operations_repository.dart';
import 'package:ephemeron/domain/sources/source_move.dart';
import 'package:ephemeron/domain/tasks/recurring_task.dart';
import 'package:ephemeron/domain/tasks/smart_filter.dart';

part 'task_repository/helpers.dart';
part 'task_repository/lists.dart';
part 'task_repository/tasks.dart';
part 'task_repository/completion.dart';
part 'task_repository/trash.dart';
part 'task_repository/move.dart';
part 'task_repository/tags.dart';
part 'task_repository/smart_lists.dart';

class TaskRepository {
  TaskRepository(this._db);

  final AppDatabase _db;
}

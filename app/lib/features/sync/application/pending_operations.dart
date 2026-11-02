// Durable 6 s undo buffer for destructive operations. Operations are written
// to SQLite immediately, applied when their timer fires (or on next launch),
// and removed from the buffer before the real mutation runs.
import 'dart:async';
import 'dart:convert';

import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/countdown_repository.dart';
import 'package:ephemeron/data/repositories/event_repository.dart';
import 'package:ephemeron/data/repositories/focus_repository.dart';
import 'package:ephemeron/data/repositories/habit_repository.dart';
import 'package:ephemeron/data/repositories/note_repository.dart';
import 'package:ephemeron/data/repositories/pending_operations_repository.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:ephemeron/features/calendar/application/calendar_providers.dart';
import 'package:ephemeron/features/countdowns/application/countdowns_providers.dart';
import 'package:ephemeron/features/focus/application/focus_providers.dart';
import 'package:ephemeron/features/habits/application/habits_providers.dart';
import 'package:ephemeron/features/notes/application/notes_providers.dart';
import 'package:ephemeron/features/tasks/application/tasks_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final pendingOperationsProvider = Provider<PendingOperations>((ref) {
  final service = PendingOperations(
    ref.watch(appDatabaseProvider),
    tasks: ref.watch(taskRepositoryProvider),
    notes: ref.watch(noteRepositoryProvider),
    habits: ref.watch(habitRepositoryProvider),
    countdowns: ref.watch(countdownRepositoryProvider),
    focus: ref.watch(focusRepositoryProvider),
    events: ref.watch(eventRepositoryProvider),
  );
  ref.onDispose(service.dispose);
  unawaited(service.start());
  return service;
});

class PendingOperations {
  PendingOperations(
    AppDatabase db, {
    required TaskRepository tasks,
    required NoteRepository notes,
    required HabitRepository habits,
    required CountdownRepository countdowns,
    required FocusRepository focus,
    required EventRepository events,
  }) : _repo = PendingOperationsRepository(db),
       _tasks = tasks,
       _notes = notes,
       _habits = habits,
       _countdowns = countdowns,
       _focus = focus,
       _events = events;

  final PendingOperationsRepository _repo;
  final TaskRepository _tasks;
  final NoteRepository _notes;
  final HabitRepository _habits;
  final CountdownRepository _countdowns;
  final FocusRepository _focus;
  final EventRepository _events;

  Timer? _timer;
  bool _applying = false;

  /// Applies operations left over from a previous session immediately, then
  /// arms the timer for the earliest queued operation.
  Future<void> start() async {
    await _applyAllPending();
    await _scheduleNext();
  }

  Future<String> scheduleTaskDelete(String id) =>
      _enqueue('task', id, 'delete');

  Future<List<String>> scheduleTaskDeleteAll(Iterable<String> ids) async {
    final out = <String>[];
    for (final id in ids) {
      out.add(await _enqueue('task', id, 'delete'));
    }
    return out;
  }

  Future<String> scheduleTaskPurge(String id) => _enqueue('task', id, 'purge');

  Future<List<String>> scheduleTaskPurgeAll(Iterable<String> ids) async {
    final out = <String>[];
    for (final id in ids) {
      out.add(await _enqueue('task', id, 'purge'));
    }
    return out;
  }

  Future<String> scheduleNoteTrash(String id) => _enqueue('note', id, 'trash');

  Future<String> scheduleFolderDelete(String id) =>
      _enqueue('folder', id, 'delete');

  Future<String> scheduleHabitArchive(String id, bool archived) =>
      _enqueue('habit', id, archived ? 'archive' : 'unarchive');

  Future<String> scheduleCountdownDelete(String id) =>
      _enqueue('countdown', id, 'delete');

  Future<String> scheduleFocusDelete(String id) =>
      _enqueue('focus', id, 'delete');

  Future<String> scheduleEventDelete(String id) =>
      _enqueue('event', id, 'delete');

  Future<String> scheduleEventDeleteOccurrence(
    String id,
    DateTime originalStartUtc, {
    required EditScope scope,
  }) => _enqueue(
    'event',
    id,
    'delete_occurrence',
    payload: jsonEncode({
      'originalStartMs': originalStartUtc.toUtc().millisecondsSinceEpoch,
      'scope': scope.name,
    }),
  );

  Future<void> cancel(String id) => _repo.cancel(id);

  Future<void> cancelAll(Iterable<String> ids) => _repo.cancelAll(ids);

  Future<String> _enqueue(
    String entity,
    String entityId,
    String op, {
    String? payload,
  }) async {
    final id = await _repo.enqueue(
      entity: entity,
      entityId: entityId,
      op: op,
      payload: payload,
    );
    await _scheduleNext();
    return id;
  }

  Future<void> _applyAllPending() async {
    if (_applying) return;
    _applying = true;
    try {
      for (final row in await _repo.all()) {
        await _applyOne(row);
      }
    } finally {
      _applying = false;
    }
  }

  Future<void> _applyDue() async {
    if (_applying) return;
    _applying = true;
    try {
      for (final row in await _repo.dueNow()) {
        await _applyOne(row);
      }
    } finally {
      _applying = false;
    }
    await _scheduleNext();
  }

  Future<void> _applyOne(PendingOperation row) async {
    try {
      await _apply(row);
      await _repo.remove(row.id);
    } catch (_) {
      // Keep the row durable so a later launch can retry it.
    }
  }

  Future<void> _scheduleNext() async {
    _timer?.cancel();
    final next = await _repo.next();
    if (next == null) return;
    final waitMs = next.scheduledAt - nowMs();
    _timer = Timer(
      Duration(milliseconds: waitMs < 0 ? 0 : waitMs),
      () => unawaited(_applyDue()),
    );
  }

  Future<void> _apply(PendingOperation row) async {
    switch (row.entity) {
      case 'task':
        switch (row.op) {
          case 'delete':
            await _tasks.softDeleteTasks([row.entityId]);
            break;
          case 'purge':
            await _tasks.purgeTask(row.entityId);
            break;
          case 'purge_batch':
            final ids = (jsonDecode(row.payload ?? '[]') as List)
                .cast<String>();
            for (final id in ids) {
              await _tasks.purgeTask(id);
            }
            break;
        }
        break;
      case 'note':
        if (row.op == 'trash') await _notes.trashNote(row.entityId);
        break;
      case 'folder':
        if (row.op == 'delete') await _notes.deleteFolder(row.entityId);
        break;
      case 'habit':
        if (row.op == 'archive' || row.op == 'unarchive') {
          await _habits.archiveHabit(row.entityId, row.op == 'archive');
        }
        break;
      case 'countdown':
        if (row.op == 'delete') await _countdowns.deleteCountdown(row.entityId);
        break;
      case 'focus':
        if (row.op == 'delete') await _focus.deleteSession(row.entityId);
        break;
      case 'event':
        switch (row.op) {
          case 'delete':
            await _events.deleteEvent(row.entityId);
            break;
          case 'delete_occurrence':
            final data =
                jsonDecode(row.payload ?? '{}') as Map<String, Object?>;
            final scopeName = data['scope'] as String? ?? 'single';
            final scope = EditScope.values.firstWhere(
              (s) => s.name == scopeName,
              orElse: () => EditScope.single,
            );
            final startMs = data['originalStartMs'] as int?;
            if (startMs != null) {
              await _events.deleteOccurrence(
                row.entityId,
                DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true),
                scope: scope,
              );
            }
            break;
        }
        break;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

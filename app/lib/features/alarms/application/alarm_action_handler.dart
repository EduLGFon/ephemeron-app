import 'dart:async';

// drift query extensions (equals, select).
// ignore: unused_import
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/db_provider.dart';
import '../../../core/platform/system_launcher.dart';
import '../../../data/services/alarm_cancel.dart';
import '../../../domain/habits/date_key.dart';
import '../../habits/application/habits_providers.dart';
import '../../tasks/application/tasks_providers.dart';
import 'alarm_providers.dart';

const _actionDone = 'com.spotnik.ephemeron.DONE';
const _actionPlusOne = 'com.spotnik.ephemeron.PLUS_ONE';

String _baseSourceId(String sourceId) {
  final at = sourceId.indexOf('@');
  if (at >= 0) return sourceId.substring(0, at);
  final hash = sourceId.indexOf('#');
  return hash >= 0 ? sourceId.substring(0, hash) : sourceId;
}

String _habitDayKey(String sourceId) {
  final at = sourceId.indexOf('@');
  if (at >= 0 && at + 1 < sourceId.length) return sourceId.substring(at + 1);
  return habitDateKey(DateTime.now());
}

Future<void> processAlarmActionPayload(WidgetRef ref, String payload) async {
  final parts = payload.split('|');
  if (parts.length < 4) return;
  final action = parts[0];
  final requestCode = int.tryParse(parts[1]) ?? -1;
  final sourceType = parts[2];
  final sourceId = parts[3];
  if (sourceType.isEmpty || sourceId.isEmpty) {
    if (requestCode >= 0) {
      try {
        await ref.read(alarmRepositoryProvider).dismissRequest(requestCode);
      } catch (_) {}
    }
    return;
  }
  final baseId = _baseSourceId(sourceId);
  final isTask =
      sourceType == 'task' ||
      sourceType == 'task_reminder' ||
      sourceType == 'task_due_tomorrow';
  final isHabit = sourceType == 'habit' || sourceType == 'habit_reminder';
  try {
    final db = ref.read(appDatabaseProvider);
    if (isTask && action == _actionDone) {
      final task = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(baseId))).getSingleOrNull();
      if (task != null && task.completedAt == null) {
        await ref.read(taskRepositoryProvider).completeTask(baseId);
      }
      await cancelAlarmsForEntity(db, baseId);
    } else if (isHabit && action == _actionPlusOne) {
      final dayKey = _habitDayKey(sourceId);
      final habit = await (db.select(
        db.habits,
      )..where((h) => h.id.equals(baseId))).getSingleOrNull();
      final rawStep = habit?.increment;
      final step = (rawStep == null || rawStep == 0) ? 1.0 : rawStep;
      await ref.read(habitRepositoryProvider).addAmount(baseId, dayKey, step);
      // addAmount cancels on reaching done; still ensure this occurrence is gone.
      await cancelHabitDayAlarms(db, baseId, dayKey);
    } else if (isHabit && action == _actionDone) {
      final dayKey = _habitDayKey(sourceId);
      await ref.read(habitRepositoryProvider).logDone(baseId, dayKey);
      await cancelHabitDayAlarms(db, baseId, dayKey);
    } else if (requestCode >= 0) {
      // Event/countdown ack or unknown completable: dismiss.
      await ref.read(alarmRepositoryProvider).dismissRequest(requestCode);
    }
  } catch (_) {
    // Best effort: native side already dismissed the notification/ring.
  }
  // Rebuild alarm window so a completed recurring source gets its next
  // instance and stale rows are cleaned up.
  try {
    await ref.read(alarmRepositoryProvider).rebuildWindow();
  } catch (_) {}
}

/// Mount once near the app shell. Processes alarm notification actions
/// (DONE/+1) that require Dart-side source completion.
class AlarmActionHandler extends ConsumerStatefulWidget {
  const AlarmActionHandler({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AlarmActionHandler> createState() => _AlarmActionHandlerState();
}

class _AlarmActionHandlerState extends ConsumerState<AlarmActionHandler>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _sub;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemLauncher.ensureAlarmActionHandler();
    _sub = SystemLauncher.alarmActions.listen(_handle);
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePending());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _consumePending();
  }

  Future<void> _consumePending() async {
    try {
      final payload = await SystemLauncher.consumeAlarmAction();
      if (payload != null) await _handle(payload);
    } catch (_) {}
  }

  Future<void> _handle(String payload) async {
    if (_processing || !mounted) return;
    _processing = true;
    try {
      await processAlarmActionPayload(ref, payload);
    } finally {
      _processing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

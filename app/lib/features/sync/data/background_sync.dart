// Periodic background sync via WorkManager (PLAN 6.1).
// Foreground auto-sync stops when the OS kills the app; this registers a
// constrained periodic task (network connected, battery not low) that runs
// headless: it reopens the Drift database, restores stored credentials from
// the keystore, and runs the Google + backend engines best-effort.
// Google data still never touches the backend: the two engines share only
// the local database handle.
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/config/app_config.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/remote/backend_sync_api.dart';
import '../../../data/remote/google_api_client.dart';
import '../../../data/repositories/countdown_repository.dart';
import '../../../data/repositories/focus_repository.dart';
import '../../../data/repositories/habit_repository.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../auth/data/backend_auth.dart';
import '../../auth/data/google_auth.dart';
import '../data/backend_sync_engine.dart';
import '../data/sync_engine.dart';

const _taskName = 'ephemeron-periodic-sync';

/// Pushes real widget payloads from a headless DB handle (no Riverpod).
/// Best-effort: every step is guarded so sync never fails because of widgets.
Future<void> _pushHeadlessWidgets(AppDatabase db) async {
  Future<void> push(
    String prefix,
    String provider,
    String title,
    String body,
  ) async {
    try {
      await HomeWidget.saveWidgetData<String>('${prefix}_title', title);
      await HomeWidget.saveWidgetData<String>('${prefix}_body', body);
      await HomeWidget.updateWidget(
        androidName: provider,
        qualifiedAndroidName: 'com.spotnik.ephemeron.$provider',
      );
    } catch (_) {}
  }

  try {
    final tasks = await TaskRepository(db).watchOpen().first;
    final titles = tasks.take(5).map((t) => t.title).toList();
    await push(
      'pending_tasks',
      'PendingTasksWidgetProvider',
      'Pending tasks',
      titles.isEmpty ? 'No pending tasks.' : titles.join('\n'),
    );
    try {
      final items = tasks
          .take(5)
          .map((t) => '{"id":"${t.id}","title":"${t.title.replaceAll('"', '')}"}')
          .join(',');
      await HomeWidget.saveWidgetData<String>(
        'pending_tasks_collection_items',
        '[$items]',
      );
      await HomeWidget.saveWidgetData<String>(
        'pending_tasks_collection_title',
        'Pending tasks',
      );
      await HomeWidget.updateWidget(
        androidName: 'PendingTasksCollectionProvider',
        qualifiedAndroidName:
            'com.spotnik.ephemeron.PendingTasksCollectionProvider',
      );
    } catch (_) {}
  } catch (_) {}
  try {
    final habits =
        await HabitRepository(db).watchHabits(archived: false).first;
    await push(
      'habits_today',
      'HabitsTodayWidgetProvider',
      'Habits today',
      habits.isEmpty ? 'No habits.' : '${habits.length} habits tracked',
    );
  } catch (_) {}
  try {
    final countdowns = await CountdownRepository(db).watchCountdowns().first;
    if (countdowns.isNotEmpty) {
      final next = countdowns.first;
      final target = DateTime.tryParse(next.targetDate ?? '') ?? DateTime.now();
      final days = target.difference(DateTime.now()).inDays;
      await push(
        'countdown',
        'CountdownWidgetProvider',
        next.title,
        '$days days remaining',
      );
    }
  } catch (_) {}
  try {
    final notes = await NoteRepository(db).watchNotesInFolder(null).first;
    if (notes.isNotEmpty) {
      final body = notes.first.body ?? '';
      await push(
        'one_note',
        'OneNoteWidgetProvider',
        notes.first.title,
        body.length > 120 ? body.substring(0, 120) : body,
      );
    }
  } catch (_) {}
  try {
    final session = await FocusRepository(db).currentSession();
    await push(
      'focus_timer',
      'FocusTimerWidgetProvider',
      session == null ? 'Focus' : 'Focusing',
      session == null ? 'No active session.' : 'Session running',
    );
  } catch (_) {}
}

@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != _taskName) return true;
    try {
      final db = AppDatabase();
      try {
        final googleAuth = GoogleAuth();
        await googleAuth.restore();
        for (final account in googleAuth.accounts) {
          await googleAuth.setActiveAccount(account);
          final engine = SyncEngine(
            db,
            clientFactory: () {
              try {
                return HttpGoogleApiClient(
                  accessToken: () => googleAuth.accessToken(),
                );
              } catch (_) {
                return null;
              }
            },
            account: account,
          );
          await engine.syncNow();
        }
        final backendAuth = BackendAuth();
        await backendAuth.restore();
        if (backendAuth.isSignedIn && AppConfig.backendBaseUrl.isNotEmpty) {
          final backend = BackendSyncEngine(
            db,
            backendAuth,
            apiFactory: (token) => HttpBackendSyncApi(accessToken: token),
          );
          await backend.syncNow();
        }
        try {
          await _pushHeadlessWidgets(db);
          await HomeWidget.saveWidgetData<String>('sync_status_title', 'Synced');
          await HomeWidget.saveWidgetData<String>(
            'sync_status_body',
            'Updated ${DateTime.now().toLocal()}',
          );
          await HomeWidget.updateWidget(
            androidName: 'SyncStatusWidgetProvider',
            qualifiedAndroidName:
                'com.spotnik.ephemeron.SyncStatusWidgetProvider',
          );
        } catch (_) {}
      } finally {
        await db.close();
      }
      return true;
    } catch (e) {
      debugPrint('[bg-sync] failed: $e');
      // Retry with backoff rather than dropping the schedule.
      return false;
    }
  });
}

class BackgroundSync {
  /// Registers or replaces the periodic task. intervalMin is clamped to the
  /// WorkManager 15-minute minimum; 0 cancels the task. Android and iOS
  /// only; other platforms are no-ops.
  static Future<void> reschedule(int intervalMin) async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      await Workmanager().initialize(backgroundSyncDispatcher);
      if (intervalMin <= 0) {
        await Workmanager().cancelByUniqueName(_taskName);
        return;
      }
      final minutes = intervalMin < 15 ? 15 : intervalMin;
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: Duration(minutes: minutes),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );
    } catch (e) {
      debugPrint('[bg-sync] schedule failed: $e');
    }
  }
}

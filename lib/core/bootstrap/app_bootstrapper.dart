import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/alarms/application/alarm_action_manager_provider.dart';
import '../../features/alarms/application/alarm_scheduler_provider.dart';
import '../../features/auth/google/google_auth_provider.dart';
import '../../features/countdown/application/countdown_providers.dart';
import '../../features/habits/application/habit_providers.dart';
import '../../features/sync/application/sync_service.dart';
import '../settings/power_saving_manager.dart';

final appBootstrapperProvider = Provider<void>((ref) {
  Future.wait([
    _safeInit(() => ref.read(alarmSchedulerInitProvider)),
    _safeInit(() => ref.read(habitAlarmsRefreshProvider)),
    _safeInit(() => ref.read(countdownAlarmsRefreshProvider)),
    _safeInit(() => ref.read(alarmActionManagerProvider)),
    _safeInit(() => ref.read(powerSavingManagerProvider)),
    _safeInit(() => ref.read(googleAuthInitProvider)),
    _safeInit(() => ref.read(syncServiceProvider)),
  ]);
});

Future<void> _safeInit(dynamic Function() initFn) async {
  try {
    final result = initFn();
    if (result is Future) {
      await result;
    }
  } catch (_) {
    // Ignore errors for isolation
  }
}

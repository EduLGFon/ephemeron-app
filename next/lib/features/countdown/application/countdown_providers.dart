import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../data/local/database_provider.dart';
import '../../alarms/application/alarm_scheduler_provider.dart';
import '../data/countdown_repository.dart';

final countdownRepositoryProvider = Provider<CountdownRepository>((ref) {
  return CountdownRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(alarmSchedulerProvider),
  );
});

final countdownsProvider = StreamProvider<List<Countdown>>((ref) {
  return ref.watch(countdownRepositoryProvider).watchCountdowns();
});

/// Catches up yearly countdown alarms whose current occurrence already
/// passed — same startup-wiring pattern as
/// habitAlarmsRefreshProvider, and for the same reason (see
/// CountdownRepository.refreshYearlyAlarms's doc comment).
final countdownAlarmsRefreshProvider = FutureProvider<void>((ref) async {
  await ref.watch(alarmSchedulerInitProvider.future);
  await ref.watch(countdownRepositoryProvider).refreshYearlyAlarms();
});

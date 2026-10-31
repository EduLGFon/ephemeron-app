// Riverpod providers for countdowns. UI reads only from Drift streams.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/db_provider.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/repositories/countdown_repository.dart';

final countdownRepositoryProvider = Provider<CountdownRepository>((ref) {
  return CountdownRepository(ref.watch(appDatabaseProvider));
});

final countdownsProvider = StreamProvider<List<Countdown>>((ref) {
  return ref.watch(countdownRepositoryProvider).watchCountdowns();
});

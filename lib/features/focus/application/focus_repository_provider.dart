import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database_provider.dart';
import '../../habits/application/habit_providers.dart';
import '../data/focus_repository.dart';

final focusRepositoryProvider = Provider<FocusRepository>((ref) {
  return FocusRepository(ref.watch(appDatabaseProvider), ref.watch(habitRepositoryProvider));
});

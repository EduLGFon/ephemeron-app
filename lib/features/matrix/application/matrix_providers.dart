import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../tasks/application/task_providers.dart';
import '../domain/matrix_quadrant.dart';

class ShowCompletedMatrixTasksNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final showCompletedMatrixTasksProvider = NotifierProvider<ShowCompletedMatrixTasksNotifier, bool>(() {
  return ShowCompletedMatrixTasksNotifier();
});

final pendingMatrixTasksProvider = StreamProvider.family<List<Task>, MatrixQuadrant>((ref, quadrant) async* {
  final repo = ref.watch(taskRepositoryProvider);
  final sortOption = ref.watch(taskSortOptionProvider);
  yield* repo.watchMatrixTasks(quadrant, isCompleted: false, sortOption: sortOption);
});

final completedMatrixTasksProvider = StreamProvider.family<List<Task>, MatrixQuadrant>((ref, quadrant) async* {
  final repo = ref.watch(taskRepositoryProvider);
  yield* repo.watchMatrixTasks(quadrant, isCompleted: true);
});


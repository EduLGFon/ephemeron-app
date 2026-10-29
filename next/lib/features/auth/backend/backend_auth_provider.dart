import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_auth_repository.dart';
import 'http_backend_auth_repository.dart';

final backendAuthRepositoryProvider = Provider<BackendAuthRepository>((ref) {
  return HttpBackendAuthRepository();
});

final backendAuthInitProvider = FutureProvider<void>((ref) async {
  final repo = ref.watch(backendAuthRepositoryProvider);
  await repo.restoreSession();
});

final backendSessionProvider = StreamProvider<BackendSession?>((ref) async* {
  await ref.watch(backendAuthInitProvider.future);
  final repo = ref.watch(backendAuthRepositoryProvider);
  yield repo.currentSession;
  yield* repo.sessionChanges;
});

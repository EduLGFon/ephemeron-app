// Sync providers: engine, status, manual triggers, auto-sync schedule.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/db/db_provider.dart';
import '../../../data/remote/backend_sync_api.dart';
import '../../../data/remote/google_api_client.dart';
import '../../auth/application/auth_providers.dart';
import '../data/microsoft_sync_engine.dart';
import '../data/microsoft_graph_client.dart';
import '../../calendar/application/calendar_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../settings/data/settings_repository.dart';
import '../../../core/power/power_saving_manager.dart';
import '../data/backend_sync_engine.dart';
import '../data/background_sync.dart';
import '../data/sync_engine.dart';

part 'sync_providers/google_sync_status.dart';
part 'sync_providers/google_auto_sync.dart';
part 'sync_providers/backend_sync.dart';

final googleApiClientProvider = Provider<GoogleApiClient>((ref) {
  final auth = ref.watch(googleAuthProvider);
  return HttpGoogleApiClient(accessToken: auth.accessToken);
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SyncEngine(
    db,
    clientFactory: () {
      try {
        return ref.read(googleApiClientProvider);
      } catch (_) {
        return null;
      }
    },
  );
});

final failedChangesProvider = StreamProvider((ref) {
  return ref.watch(syncEngineProvider).watchFailed();
});

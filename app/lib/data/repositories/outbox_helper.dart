// Shared outbox enqueue helper. Single source of truth for queuing
// mutations for sync.
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';

Future<void> enqueueOutbox(
  AppDatabase db, {
  required String entity,
  required String entityId,
  required String op,
}) {
  return db.into(db.outbox).insert(
        OutboxCompanion.insert(
          id: newId(),
          entity: entity,
          entityId: entityId,
          op: op,
          createdAt: nowMs(),
        ),
      );
}
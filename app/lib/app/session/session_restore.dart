// Session restore: last screen, open sheet/modal, calendar view,
// in-progress drafts. Lightweight UI state lives in SharedPreferences
// (via SettingsRepository, sync read for fast startup); form contents
// live in the Drift `drafts` table, autosaved debounced at 500 ms.
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db_provider.dart';
import '../../data/drift/app_database.dart';

/// Silent auto-reopen below this age, confirm banner below expiry.
const silentRestoreWindowMs = 24 * 60 * 60 * 1000;

/// Drafts older than this are deleted and never restored.
const draftExpiryMs = 7 * 24 * 60 * 60 * 1000;

/// Debounce for draft writes: never write on every keystroke synchronously.
const draftDebounce = Duration(milliseconds: 500);

bool draftIsExpired(int updatedAtMs, int nowMs) =>
    nowMs - updatedAtMs > draftExpiryMs;

bool draftNeedsConfirm(int updatedAtMs, int nowMs) =>
    nowMs - updatedAtMs > silentRestoreWindowMs &&
    !draftIsExpired(updatedAtMs, nowMs);

String draftIdFor(String formType, String? entityId) =>
    entityId == null ? formType : '$formType:$entityId';

class DraftStore {
  DraftStore(this._db);
  final AppDatabase _db;

  Future<void> save(
    String formType,
    String? entityId,
    Map<String, dynamic> json,
  ) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db
        .into(_db.drafts)
        .insertOnConflictUpdate(
          DraftsCompanion.insert(
            id: draftIdFor(formType, entityId),
            formType: formType,
            entityId: Value(entityId),
            json: jsonEncode(json),
            updatedAt: now,
          ),
        );
  }

  Future<({Map<String, dynamic> json, int updatedAtMs})?> load(
    String formType,
    String? entityId,
  ) async {
    final row =
        await (_db.select(_db.drafts)
              ..where((d) => d.id.equals(draftIdFor(formType, entityId))))
            .getSingleOrNull();
    if (row == null) return null;
    try {
      final decoded = jsonDecode(row.json) as Map<String, dynamic>;
      return (json: decoded, updatedAtMs: row.updatedAt);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear(String formType, String? entityId) async {
    await (_db.delete(
      _db.drafts,
    )..where((d) => d.id.equals(draftIdFor(formType, entityId)))).go();
  }

  /// Deletes expired drafts. Returns the number removed.
  Future<int> clearExpired([int? nowMs]) async {
    final now = nowMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    final cutoff = now - draftExpiryMs;
    return _db.transaction(() async {
      final old = await (_db.select(
        _db.drafts,
      )..where((d) => d.updatedAt.isSmallerThanValue(cutoff))).get();
      await (_db.delete(
        _db.drafts,
      )..where((d) => d.updatedAt.isSmallerThanValue(cutoff))).go();
      return old.length;
    });
  }
}

final draftStoreProvider = Provider<DraftStore>((ref) {
  return DraftStore(ref.watch(appDatabaseProvider));
});

/// Debounced draft writer. Call [changed] on every form change with a
/// snapshot closure; the write happens 500 ms after the last change and
/// never blocks the UI thread synchronously.
class DraftAutosaver {
  DraftAutosaver(this._store, this._formType, this._entityId);

  final DraftStore _store;
  final String _formType;
  final String? _entityId;
  Timer? _timer;
  Map<String, dynamic> Function()? _latest;

  void changed(Map<String, dynamic> Function() snapshot) {
    _latest = snapshot;
    _timer?.cancel();
    _timer = Timer(draftDebounce, flush);
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final snap = _latest;
    _latest = null;
    if (snap == null) return;
    try {
      final data = snap();
      if (_isEmpty(data)) {
        await _store.clear(_formType, _entityId);
      } else {
        await _store.save(_formType, _entityId, data);
      }
    } catch (_) {
      // Best-effort: drafts must never break the form.
    }
  }

  Future<void> discard() async {
    _timer?.cancel();
    _timer = null;
    _latest = null;
    try {
      await _store.clear(_formType, _entityId);
    } catch (_) {}
  }

  void dispose() {
    _timer?.cancel();
    final snap = _latest;
    _latest = null;
    if (snap != null) {
      // Fire-and-forget flush so kills during typing still persist.
      unawaited(() async {
        try {
          final data = snap();
          if (_isEmpty(data)) {
            await _store.clear(_formType, _entityId);
          } else {
            await _store.save(_formType, _entityId, data);
          }
        } catch (_) {}
      }());
    }
  }

  bool _isEmpty(Map<String, dynamic> data) {
    for (final v in data.values) {
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      if (v is List && v.isEmpty) continue;
      if (v is Map && v.isEmpty) continue;
      if (v is num && v == 0) continue;
      if (v is bool && !v) continue;
      return false;
    }
    return true;
  }
}

// Focus sessions: timestamp-based timers. Elapsed computed per frame
// from stored timestamps; one native alarm ends the phase. State
// survives app kill, reboot and sleep.
import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/data/drift/app_database.dart';

class FocusRepository {
  FocusRepository(this._db);
  final AppDatabase _db;
  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// Starts a session targeting [durationMin]; returns the session id.
  Future<String> startSession({
    String? taskId,
    String? habitId,
    required int durationMin,
    String phase = 'focus',
  }) async {
    final id = newId();
    final now = _now();
    await _db
        .into(_db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            id: id,
            taskId: Value(taskId),
            habitId: Value(habitId),
            startUtc: now,
            targetEndUtc: Value(now + durationMin * 60000),
            phase: Value(phase),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  /// The currently running session, if any.
  Future<FocusSession?> currentSession() {
    return (_db.select(_db.focusSessions)
          ..where((f) => f.endUtc.isNull())
          ..orderBy([(f) => OrderingTerm.desc(f.startUtc)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Finishes a session. Returns kept minutes for task/habit credit.
  Future<int> finishSession(
    String id, {
    bool abandoned = false,
    String? note,
  }) async {
    final s = await (_db.select(
      _db.focusSessions,
    )..where((f) => f.id.equals(id))).getSingleOrNull();
    if (s == null) return 0;
    final end = _now();
    await (_db.update(_db.focusSessions)..where((f) => f.id.equals(id))).write(
      FocusSessionsCompanion(
        endUtc: Value(end),
        note: note == null ? const Value.absent() : Value(note),
        updatedAt: Value(end),
      ),
    );
    return ((end - s.startUtc) / 60000).floor().clamp(0, 1 << 30);
  }

  /// Deletes a session without credit (discard).
  Future<void> deleteSession(String id) async {
    await (_db.delete(_db.focusSessions)..where((f) => f.id.equals(id))).go();
  }

  /// Total focused minutes in [fromUtc, toUtc].
  Future<int> totalMinutes(int fromUtc, int toUtc) async {
    final rows =
        await (_db.select(_db.focusSessions)..where(
              (f) =>
                  f.startUtc.isBiggerOrEqualValue(fromUtc) &
                  f.startUtc.isSmallerThanValue(toUtc),
            ))
            .get();
    var total = 0;
    for (final r in rows) {
      final end = r.endUtc ?? toUtc;
      if (end > r.startUtc) {
        total += ((end - r.startUtc) / 60000).floor();
      }
    }
    return total;
  }

  Stream<List<FocusSession>> watchRecent({int limit = 50}) {
    final q = _db.select(_db.focusSessions)
      ..orderBy([(f) => OrderingTerm.desc(f.startUtc)])
      ..limit(limit);
    return q.watch();
  }
}

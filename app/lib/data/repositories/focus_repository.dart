// Focus sessions: timestamp-based timers. Elapsed computed per frame
// from stored timestamps; one native alarm ends the phase. State
// survives app kill, reboot and sleep.
import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/pending_operations_repository.dart';

class FocusRepository {
  FocusRepository(this._db);
  final AppDatabase _db;
  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// Focus/stopwatch sessions shorter than this are excluded from focus stats.
  static const minQualifyingFocusMinutes = 5;

  /// Floor minutes for [s] at [atUtc] (defaults to now for running sessions).
  static int sessionMinutes(FocusSession s, {int? atUtc}) {
    final end =
        s.endUtc ?? atUtc ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    if (end <= s.startUtc) return 0;
    return ((end - s.startUtc) / msPerMinute).floor();
  }

  static bool isBreakSession(FocusSession s) => s.phase == 'break';

  /// Qualifying focus work: not a break and at least [minQualifyingFocusMinutes].
  /// Stopwatch sessions count as focus work when long enough.
  static bool isQualifyingFocusSession(FocusSession s, {int? atUtc}) {
    if (isBreakSession(s)) return false;
    return sessionMinutes(s, atUtc: atUtc) >= minQualifyingFocusMinutes;
  }

  /// Starts a session targeting [durationMin]; returns the session id.
  /// A null [durationMin] starts an open-ended stopwatch session with no
  /// target end and no end alarm (unless a [phase] is supplied).
  Future<String> startSession({
    String? taskId,
    String? habitId,
    int? durationMin,
    String? phase,
    String? alarmPreset,
  }) async {
    final id = newId();
    final now = _now();
    final resolvedPhase =
        phase ?? (durationMin == null ? 'stopwatch' : 'focus');
    await _db
        .into(_db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            id: id,
            taskId: Value(taskId),
            habitId: Value(habitId),
            startUtc: now,
            targetEndUtc: Value(
              durationMin == null ? null : now + durationMin * msPerMinute,
            ),
            phase: Value(resolvedPhase),
            alarmPreset: Value(alarmPreset),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  /// The currently running session, if any.
  Future<FocusSession?> currentSession() {
    return (_db.select(_db.focusSessions)
          ..where(
            (f) =>
                f.endUtc.isNull() &
                f.id.isNotInQuery(
                  pendingIdsQuery(_db, entity: 'focus', ops: const {'delete'}),
                ),
          )
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
    return ((end - s.startUtc) / msPerMinute).floor().clamp(0, 1 << 30);
  }

  /// Deletes a session without credit (discard).
  Future<void> deleteSession(String id) async {
    await (_db.delete(_db.focusSessions)..where((f) => f.id.equals(id))).go();
  }

  /// Total qualifying focus minutes in [fromUtc, toUtc]. Excludes breaks and
  /// focus/stopwatch sessions shorter than [minQualifyingFocusMinutes].
  Future<int> totalMinutes(int fromUtc, int toUtc) =>
      totalFocusMinutes(fromUtc, toUtc);

  Future<int> totalFocusMinutes(int fromUtc, int toUtc) async {
    final rows = await sessionsInRange(fromUtc, toUtc);
    var total = 0;
    for (final r in rows) {
      if (!isQualifyingFocusSession(r, atUtc: toUtc)) continue;
      final start = r.startUtc.clamp(fromUtc, toUtc);
      final end = (r.endUtc ?? toUtc).clamp(fromUtc, toUtc);
      if (end > start) total += ((end - start) / msPerMinute).floor();
    }
    return total;
  }

  /// Total break minutes in [fromUtc, toUtc], any duration.
  Future<int> totalBreakMinutes(int fromUtc, int toUtc) async {
    final rows = await sessionsInRange(fromUtc, toUtc);
    var total = 0;
    for (final r in rows) {
      if (!isBreakSession(r)) continue;
      final start = r.startUtc.clamp(fromUtc, toUtc);
      final end = (r.endUtc ?? toUtc).clamp(fromUtc, toUtc);
      if (end > start) total += ((end - start) / msPerMinute).floor();
    }
    return total;
  }

  /// Finished sessions overlapping [fromUtc, toUtc], newest last.
  Future<List<FocusSession>> sessionsInRange(int fromUtc, int toUtc) {
    return (_db.select(_db.focusSessions)..where(
          (f) =>
              f.startUtc.isSmallerThanValue(toUtc) &
              (f.endUtc.isNull() | f.endUtc.isBiggerOrEqualValue(fromUtc)) &
              f.id.isNotInQuery(
                pendingIdsQuery(_db, entity: 'focus', ops: const {'delete'}),
              ),
        ))
        .get();
  }

  Stream<List<FocusSession>> watchRecent({int limit = 50}) {
    final q = _db.select(_db.focusSessions)
      ..where(
        (f) => f.id.isNotInQuery(
          pendingIdsQuery(_db, entity: 'focus', ops: const {'delete'}),
        ),
      )
      ..orderBy([(f) => OrderingTerm.desc(f.startUtc)])
      ..limit(limit);
    return q.watch();
  }
}

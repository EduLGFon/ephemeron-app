// Countdowns. Local-first.
import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/search/sanitize.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';

class CountdownRepository {
  CountdownRepository(this._db);
  final AppDatabase _db;

  Future<String> createCountdown({
    required String title,
    String? targetDate,
    bool yearlyRepeat = false,
    bool showAge = false,
    String? notes,
    String? type,
    int? alertOffsetDays,
    int? alertTimeMin,
    String? alarmPreset,
  }) async {
    final id = newId();
    final now = nowMs();
    await _db
        .into(_db.countdowns)
        .insert(
          CountdownsCompanion.insert(
            id: id,
            title: title,
            type: Value(type),
            targetDate: Value(targetDate),
            yearlyRepeat: Value(yearlyRepeat),
            showAge: Value(showAge),
            notes: Value(notes),
            alertOffsetDays: Value(alertOffsetDays),
            alertTimeMin: Value(alertTimeMin),
            alarmPreset: Value(alarmPreset),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Stream<List<Countdown>> watchCountdowns() {
    final q = _db.select(_db.countdowns)..where((c) => c.deletedAt.isNull());
    q.orderBy([(c) => OrderingTerm.asc(c.targetDate)]);
    return q.watch();
  }

  /// Global-search hits over live countdowns.
  Future<List<Countdown>> searchCountdowns(
    String query, {
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final stripped = sanitizeSearch(q);
    if (stripped.isEmpty) return [];
    final like = '%$stripped%';
    return (_db.select(_db.countdowns)
          ..where((c) => c.deletedAt.isNull() & c.title.like(like))
          ..orderBy([(c) => OrderingTerm.asc(c.targetDate)])
          ..limit(limit))
        .get();
  }

  Future<void> updateCountdown(
    String id, {
    String? title,
    String? Function()? targetDate,
    bool? yearlyRepeat,
    bool? showAge,
    String? Function()? notes,
    int? Function()? alertOffsetDays,
    int? Function()? alertTimeMin,
    String? Function()? alarmPreset,
  }) async {
    await (_db.update(_db.countdowns)..where((c) => c.id.equals(id))).write(
      CountdownsCompanion(
        title: title == null ? const Value.absent() : Value(title),
        targetDate: targetDate == null
            ? const Value.absent()
            : Value(targetDate()),
        yearlyRepeat: yearlyRepeat == null
            ? const Value.absent()
            : Value(yearlyRepeat),
        showAge: showAge == null ? const Value.absent() : Value(showAge),
        notes: notes == null ? const Value.absent() : Value(notes()),
        alertOffsetDays: alertOffsetDays == null
            ? const Value.absent()
            : Value(alertOffsetDays()),
        alertTimeMin: alertTimeMin == null
            ? const Value.absent()
            : Value(alertTimeMin()),
        alarmPreset: alarmPreset == null
            ? const Value.absent()
            : Value(alarmPreset()),
        updatedAt: Value(nowMs()),
      ),
    );
  }

  Future<void> restoreCountdown(String id) async {
    await (_db.update(_db.countdowns)..where((c) => c.id.equals(id))).write(
      CountdownsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(nowMs()),
      ),
    );
  }

  Future<void> deleteCountdown(String id) async {
    await (_db.update(_db.countdowns)..where((c) => c.id.equals(id))).write(
      CountdownsCompanion(deletedAt: Value(nowMs()), updatedAt: Value(nowMs())),
    );
  }
}

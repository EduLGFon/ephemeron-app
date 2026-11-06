part of '../habit_repository.dart';

mixin _HabitSectionOps on _HabitRepositoryBase {
  Future<String> createSection(String name) async {
    final id = newId();
    final now = nowMs();
    await _db
        .into(_db.habitSections)
        .insert(
          HabitSectionsCompanion.insert(
            id: id,
            name: name,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Stream<List<HabitSection>> watchSections() {
    return (_db.select(
      _db.habitSections,
    )..orderBy([(s) => OrderingTerm.asc(s.sortOrder)])).watch();
  }
}

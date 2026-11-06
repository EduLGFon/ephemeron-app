part of '../tables.dart';

class HabitSections extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Habits extends Table {
  TextColumn get id => text()();
  TextColumn get sectionId =>
      text().nullable().references(HabitSections, #id)();
  TextColumn get name => text()();
  TextColumn get frequency => text().withDefault(const Constant('daily'))();
  IntColumn get weekdaysMask => integer().withDefault(const Constant(0))();
  IntColumn get weeklyTarget => integer().nullable()();
  IntColumn get intervalDays => integer().nullable()();
  TextColumn get goalType => text().nullable()();
  RealColumn get goalAmount => real().nullable()();
  TextColumn get unit => text().nullable()();
  RealColumn get increment => real().nullable()();
  IntColumn get goalDurationDays => integer().nullable()();
  TextColumn get startDate => text().nullable()(); // YYYY-MM-DD
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  TextColumn get reminderTime => text().nullable()();
  TextColumn get alarmPreset => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  TextColumn get remoteId => text().nullable()();
  TextColumn get remoteEtag => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class HabitLogs extends Table {
  TextColumn get id => text()();
  TextColumn get habitId => text().references(Habits, #id)();
  TextColumn get dayKey => text()(); // YYYY-MM-DD
  RealColumn get amount => real().withDefault(const Constant(0))();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  BoolColumn get skipped => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

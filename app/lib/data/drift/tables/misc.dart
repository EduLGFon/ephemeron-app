part of '../tables.dart';

class Countdowns extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get type => text().nullable()();
  TextColumn get template => text().nullable()();
  TextColumn get targetDate => text().nullable()(); // YYYY-MM-DD
  BoolColumn get yearlyRepeat => boolean().withDefault(const Constant(false))();
  BoolColumn get showAge => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  IntColumn get alertOffsetDays => integer().nullable()();
  IntColumn get alertTimeMin => integer().nullable()();
  TextColumn get alarmPreset => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class FocusSessions extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text().nullable()();
  TextColumn get habitId => text().nullable()();
  IntColumn get startUtc => integer()();
  IntColumn get endUtc => integer().nullable()();
  IntColumn get targetEndUtc => integer().nullable()();
  TextColumn get phase => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get alarmPreset => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class AlarmsIndex extends Table {
  TextColumn get id => text()();
  TextColumn get sourceType => text()();
  TextColumn get sourceId => text()();
  IntColumn get fireAtUtc => integer()();
  IntColumn get presetStep => integer().nullable()();
  IntColumn get requestCode => integer().nullable()();
  TextColumn get state => text().withDefault(const Constant('scheduled'))();
  // v5: kind is reminder|alarm, preset is AlarmPreset.id, title is display.
  TextColumn get kind => text().withDefault(const Constant('alarm'))();
  TextColumn get title => text().nullable()();
  TextColumn get preset => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Outbox extends Table {
  TextColumn get id => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get op => text()();
  TextColumn get payload => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get nextTryAt => integer().nullable()();
  TextColumn get lastError => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();
  IntColumn get lastSyncAt => integer().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Durable buffer for destructive operations that apply after a short undo
/// window. Rows survive app restarts and are applied on next launch.
class PendingOperations extends Table {
  TextColumn get id => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get op => text()();
  TextColumn get payload => text().nullable()();
  IntColumn get scheduledAt => integer()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Drafts extends Table {
  TextColumn get id => text()();
  TextColumn get formType => text()();
  TextColumn get entityId => text().nullable()();
  TextColumn get json => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

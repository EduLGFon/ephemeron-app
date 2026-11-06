part of '../tables.dart';

class TaskLists extends Table {
  TextColumn get id => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get color => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  TextColumn get remoteEtag => text().nullable()();
  TextColumn get googleAccount => text().nullable()();
  TextColumn get microsoftAccount => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get listId => text().nullable().references(TaskLists, #id)();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get notes => text().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get dueDate => text().nullable()(); // YYYY-MM-DD
  TextColumn get plannedDate => text().nullable()(); // YYYY-MM-DD
  TextColumn get plannedStart =>
      text().nullable()(); // local ISO YYYY-MM-DDTHH:mm
  TextColumn get plannedEnd =>
      text().nullable()(); // local ISO YYYY-MM-DDTHH:mm
  TextColumn get seriesId => text().nullable()();
  TextColumn get recurrenceKey =>
      text().nullable()(); // YYYY-MM-DD occurrence date
  IntColumn get dueTime => integer().nullable()(); // ms of day? store minutes
  IntColumn get durationMin => integer().nullable()();
  TextColumn get rrule => text().nullable()();
  TextColumn get repeatMode => text().nullable()();
  TextColumn get parentId => text().nullable()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get wontDo => boolean().withDefault(const Constant(false))();
  IntColumn get completedAt => integer().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get alarmPreset => text().nullable()();
  TextColumn get reminders => text().nullable()(); // json offsets, local-only
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  TextColumn get remoteId => text().nullable()();
  TextColumn get remoteEtag => text().nullable()();
  TextColumn get googleAccount => text().nullable()();
  TextColumn get microsoftAccount => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class TaskTags extends Table {
  TextColumn get taskId => text().references(Tasks, #id)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {taskId, tagId};
}

class SmartLists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get filterJson => text().withDefault(const Constant('{}'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get color => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class TagDefaults extends Table {
  TextColumn get tagId => text().references(Tags, #id)();
  TextColumn get defaultReminderJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {tagId};
}

/// Per-occurrence completion state for recurring task projections. Local-only;
/// never synced to Google/Microsoft task APIs. Keyed by stable series identity
/// and occurrence date (YYYY-MM-DD, same key as projection/suppression).
class TaskOccurrenceStates extends Table {
  TextColumn get seriesId => text()();
  TextColumn get occurrenceDate => text()();
  TextColumn get status => text()(); // completed | wont_do
  IntColumn get completedAt => integer().nullable()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {seriesId, occurrenceDate};
}

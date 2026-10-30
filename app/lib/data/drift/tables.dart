import 'package:drift/drift.dart';

// Common syncable columns are repeated per table (Drift has no mixins for columns
// that participate in the table definition cleanly). All timestamps are UTC ms.

class Calendars extends Table {
  TextColumn get id => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get color => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get readOnly => boolean().withDefault(const Constant(false))();
  TextColumn get source =>
      text().withDefault(const Constant('device'))(); // google/device
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  TextColumn get remoteEtag => text().nullable()();
  TextColumn get googleAccount => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Events extends Table {
  TextColumn get id => text()();
  TextColumn get calendarId => text().references(Calendars, #id)();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get notes => text().nullable()();
  TextColumn get notesOverflowNoteId => text().nullable()();
  TextColumn get location => text().nullable()();
  IntColumn get startUtc => integer().nullable()();
  IntColumn get endUtc => integer().nullable()();
  TextColumn get startDate => text().nullable()(); // YYYY-MM-DD all-day
  TextColumn get endDate => text().nullable()();
  BoolColumn get isAllDay => boolean().withDefault(const Constant(false))();
  TextColumn get tzId => text().nullable()();
  TextColumn get endTzId => text().nullable()();
  TextColumn get rrule => text().nullable()();
  TextColumn get recurringMasterId => text().nullable()();
  IntColumn get originalStart => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('confirmed'))();
  TextColumn get colorId => text().nullable()();
  TextColumn get meetUrl => text().nullable()();
  BoolColumn get createMeet => boolean().withDefault(const Constant(false))();
  TextColumn get reminders => text().nullable()(); // json
  TextColumn get alarmPreset => text().nullable()();
  TextColumn get visibility => text().nullable()();
  TextColumn get transparency => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  TextColumn get remoteId => text().nullable()();
  TextColumn get remoteEtag => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class EventAttendees extends Table {
  TextColumn get id => text()();
  TextColumn get eventId => text().references(Events, #id)();
  TextColumn get email => text()();
  TextColumn get name => text().nullable()();
  TextColumn get rsvp => text().nullable()();
  BoolColumn get isOrganizer => boolean().withDefault(const Constant(false))();
  BoolColumn get isSelf => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class OccurrenceCache extends Table {
  TextColumn get id => text()();
  TextColumn get eventId => text()();
  TextColumn get title => text().nullable()();
  TextColumn get colorId => text().nullable()();
  IntColumn get startUtc => integer()();
  IntColumn get endUtc => integer()();
  TextColumn get dayKey => text()();

  @override
  Set<Column> get primaryKey => {id};
}

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
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  TextColumn get remoteId => text().nullable()();
  TextColumn get remoteEtag => text().nullable()();

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
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get parentId => text().nullable().references(Folders, #id)();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get folderId => text().nullable().references(Folders, #id)();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().nullable()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  TextColumn get linkedEventId => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  TextColumn get remoteId => text().nullable()();
  TextColumn get remoteEtag => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class NoteLinks extends Table {
  @ReferenceName('outgoingLinks')
  TextColumn get fromNoteId => text().references(Notes, #id)();
  @ReferenceName('incomingLinks')
  TextColumn get toNoteId => text().references(Notes, #id)();

  @override
  Set<Column> get primaryKey => {fromNoteId, toNoteId};
}

class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text()();
  TextColumn get path => text()();
  TextColumn get mime => text().nullable()();
  IntColumn get size => integer().nullable()();
  TextColumn get hash => text().nullable()();
  IntColumn get createdAt => integer()();

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

class Drafts extends Table {
  TextColumn get id => text()();
  TextColumn get formType => text()();
  TextColumn get entityId => text().nullable()();
  TextColumn get json => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

const tableIdGenerator = Uuid();

@DataClassName('TaskList')
class Lists extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get name => text()();
  TextColumn get colorHex => text().withDefault(const Constant('#1B4B4A'))();
  TextColumn get backgroundHex => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isInbox => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

class Tags extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get name => text()();
  TextColumn get colorHex => text().withDefault(const Constant('#D89B3C'))();
  TextColumn get defaultAlarmPreset => text().nullable()();
  TextColumn get defaultColorHex => text().nullable()();
  TextColumn get defaultNoteFolderId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get googleTaskId => text().nullable()();
  TextColumn get listId => text().references(Lists, #id)();
  TextColumn get parentTaskId => text().nullable().references(Tasks, #id)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get dueHasTime => boolean().withDefault(const Constant(false))();
  TextColumn get recurrenceRule => text().nullable()();
  IntColumn get durationMinutes => integer().withDefault(const Constant(30))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  BoolColumn get isWontDo => boolean().withDefault(const Constant(false))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get alarmPreset => text().nullable()();
  TextColumn get reminderOffsetsMinutes => text().nullable()();
  TextColumn get scheduledAlarmIds => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

class TaskTags extends Table {
  TextColumn get taskId => text().references(Tasks, #id)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {taskId, tagId};
}

class EventTags extends Table {
  TextColumn get googleEventId => text()();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {googleEventId, tagId};
}

class Habits extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get name => text()();
  TextColumn get section => text().withDefault(const Constant('other'))();
  TextColumn get frequencyType => text()();
  TextColumn get frequencyConfig => text().nullable()();
  TextColumn get goalType => text().withDefault(const Constant('binary'))();
  RealColumn get goalAmount => real().nullable()();
  TextColumn get goalUnit => text().nullable()();
  RealColumn get logIncrement => real().withDefault(const Constant(1))();
  TextColumn get goalDuration => text().withDefault(const Constant('forever'))();
  DateTimeColumn get startDate => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get reminderHour => integer().nullable()();
  IntColumn get reminderMinute => integer().nullable()();
  TextColumn get alarmPreset => text().nullable()();
  TextColumn get scheduledAlarmIds => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

class HabitLogs extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get habitId => text().references(Habits, #id)();
  DateTimeColumn get date => dateTime()();
  RealColumn get amount => real().withDefault(const Constant(0))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {habitId, date},
      ];

  @override
  Set<Column> get primaryKey => {id};
}

class FocusSessions extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get mode => text()();
  TextColumn get linkedTaskId => text().nullable().references(Tasks, #id)();
  TextColumn get linkedHabitId => text().nullable().references(Habits, #id)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Countdowns extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get title => text()();
  TextColumn get type => text().withDefault(const Constant('custom'))();
  DateTimeColumn get targetDate => dateTime()();
  BoolColumn get isYearly => boolean().withDefault(const Constant(false))();
  BoolColumn get showAge => boolean().withDefault(const Constant(false))();
  TextColumn get scheduledAlarmIds => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class NoteFolders extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get name => text()();
  TextColumn get parentFolderId => text().nullable().references(NoteFolders, #id)();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

class Notes extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get title => text()();
  TextColumn get content => text()();
  TextColumn get folderId => text().nullable().references(NoteFolders, #id)();
  TextColumn get eventId => text().nullable()();
  TextColumn get linkedCalendarId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

class CachedCalendarEvents extends Table {
  TextColumn get id => text()();
  TextColumn get calendarId => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get location => text().nullable()();
  DateTimeColumn get start => dateTime()();
  DateTimeColumn get end => dateTime()();
  BoolColumn get isAllDay => boolean().withDefault(const Constant(false))();
  TextColumn get colorId => text().nullable()();
  TextColumn get reminderMinutes => text().nullable()();
  TextColumn get attendees => text().nullable()();
  BoolColumn get hasVideoConference => boolean().withDefault(const Constant(false))();
  TextColumn get videoConferenceLink => text().nullable()();
  TextColumn get selfResponseStatus => text().withDefault(const Constant('needsAction'))();
  TextColumn get recurrence => text().nullable()();
  TextColumn get recurringEventId => text().nullable()();
  DateTimeColumn get originalStartTime => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id, calendarId};
}

@DataClassName('CustomSmartList')
class CustomSmartLists extends Table {
  TextColumn get id => text().clientDefault(() => tableIdGenerator.v4())();
  TextColumn get name => text()();
  TextColumn get colorHex => text().withDefault(const Constant('#1B4B4A'))();
  IntColumn get minPriority => integer().nullable()();
  TextColumn get dateFilter => text().nullable()();
  TextColumn get tagId => text().nullable().references(Tags, #id)();
  BoolColumn get isCompletedFilter => boolean().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
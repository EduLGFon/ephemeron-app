part of '../tables.dart';

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
  TextColumn get microsoftAccount => text().nullable()();

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
  TextColumn get googleAccount => text().nullable()();
  TextColumn get microsoftAccount => text().nullable()();

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
  TextColumn get sourceType =>
      text().withDefault(const Constant('event'))(); // event/task

  @override
  Set<Column> get primaryKey => {id};
}

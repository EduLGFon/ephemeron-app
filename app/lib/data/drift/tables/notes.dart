part of '../tables.dart';

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

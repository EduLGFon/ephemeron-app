import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/note_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  test('nested folders, move, delete reparents to parent', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = NoteRepository(db, attachmentDir: null);
    final root = await repo.createFolder('Root');
    final child = await repo.createFolder('Child', parentId: root);
    final n = await repo.createNote(title: 'N', folderId: child);
    await repo.moveFolder(child, null);
    expect((await repo.breadcrumbs(child)).map((f) => f.name), ['Child']);
    final root2 = await repo.createFolder('Root2');
    await repo.moveFolder(child, root2);
    expect((await repo.breadcrumbs(child)).map((f) => f.name), [
      'Root2',
      'Child',
    ]);
    await repo.deleteFolder(root2);
    // Child reparented to root2's parent (null); note follows folder.
    expect((await repo.breadcrumbs(child)).map((f) => f.name), ['Child']);
    final notes = await repo.notesInFolder(child);
    expect(notes.map((e) => e.id), contains(n));
  });

  test('pin, duplicate, trash and restore', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = NoteRepository(db, attachmentDir: null);
    final id = await repo.createNote(title: 'A', body: 'hello');
    await repo.setPinned(id, true);
    final dup = await repo.duplicateNote(id);
    expect(dup, isNot(id));
    await repo.trashNote(id);
    expect(await repo.notesInFolder(null), hasLength(1));
    expect((await repo.notesInFolder(null)).single.id, dup);
    await repo.restoreNote(id);
    expect(await repo.notesInFolder(null), hasLength(2));
  });

  test('fts search finds snippet', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = NoteRepository(db, attachmentDir: null);
    await repo.createNote(title: 'Shopping', body: 'buy oat milk and honey');
    await repo.createNote(title: 'Other', body: 'unrelated text here');
    final hits = await repo.searchNotes('oat milk');
    expect(hits.length, 1);
    expect(hits.single.note.title, 'Shopping');
    expect(hits.single.snippet.toLowerCase(), contains('oat'));
  });

  test('overflow note for long event descriptions', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = NoteRepository(db, attachmentDir: null);
    final long = 'x' * 9000;
    final noteId = await repo.ensureOverflowNote('event1', long);
    expect(noteId, isNotNull);
    final note = await repo.getNote(noteId!);
    expect(note!.body!.length, greaterThan(8000));
    expect(note.linkedEventId, 'event1');
    // Idempotent: same note reused.
    expect(await repo.ensureOverflowNote('event1', long), noteId);
  });

  test('event-linked notes listed', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = NoteRepository(db, attachmentDir: null);
    await repo.createNote(title: 'Prep', linkedEventId: 'ev1');
    await repo.createNote(title: 'Plain');
    final linked = await repo.notesForEvent('ev1');
    expect(linked.map((n) => n.title), ['Prep']);
  });
}

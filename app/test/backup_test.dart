// Backup suite: export/import round-trip preserves user tables,
// malformed input throws typed errors.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/countdown_repository.dart';
import 'package:ephemeron/data/repositories/focus_repository.dart';
import 'package:ephemeron/data/repositories/habit_repository.dart';
import 'package:ephemeron/features/settings/data/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<void> _seed(AppDatabase db) async {
  final habits = HabitRepository(db);
  final sectionId = await habits.createSection('Health');
  final habitId = await habits.createHabit(name: 'Read', sectionId: sectionId);
  await habits.logDone(habitId, '2026-03-08');

  final countdowns = CountdownRepository(db);
  await countdowns.createCountdown(
    title: 'Trip',
    targetDate: '2027-06-01',
    yearlyRepeat: true,
    showAge: true,
  );

  final focus = FocusRepository(db);
  final sessionId = await focus.startSession(durationMin: 25);
  await focus.finishSession(sessionId, note: 'deep work');

  const now = 1700000000000;
  await db
      .into(db.taskLists)
      .insert(
        TaskListsCompanion.insert(
          id: 'list1',
          name: 'Inbox',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.tags)
      .insert(
        TagsCompanion.insert(
          id: 'tag1',
          name: 'home',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: 'task1',
          listId: const Value('list1'),
          title: const Value('Buy milk'),
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.taskTags)
      .insert(TaskTagsCompanion.insert(taskId: 'task1', tagId: 'tag1'));
  await db
      .into(db.calendars)
      .insert(
        CalendarsCompanion.insert(
          id: 'cal1',
          name: 'Personal',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.events)
      .insert(
        EventsCompanion.insert(
          id: 'event1',
          calendarId: 'cal1',
          title: const Value('Dentist'),
          startUtc: const Value(1800000000000),
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.eventAttendees)
      .insert(
        EventAttendeesCompanion.insert(
          id: 'att1',
          eventId: 'event1',
          email: 'a@example.com',
        ),
      );
  await db
      .into(db.folders)
      .insert(
        FoldersCompanion.insert(
          id: 'f1',
          name: 'Notes',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: 'n1',
          folderId: const Value('f1'),
          title: const Value('Shopping'),
          body: const Value('milk and eggs'),
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: 'n2',
          title: const Value('Other'),
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.noteLinks)
      .insert(NoteLinksCompanion.insert(fromNoteId: 'n1', toNoteId: 'n2'));
}

Future<Map<String, int>> _counts(AppDatabase db) async {
  Future<int> n(dynamic table) =>
      db.select(table as TableInfo<Table, dynamic>).get().then((r) => r.length);
  return {
    'calendars': await n(db.calendars),
    'events': await n(db.events),
    'event_attendees': await n(db.eventAttendees),
    'task_lists': await n(db.taskLists),
    'tasks': await n(db.tasks),
    'task_tags': await n(db.taskTags),
    'tags': await n(db.tags),
    'habit_sections': await n(db.habitSections),
    'habits': await n(db.habits),
    'habit_logs': await n(db.habitLogs),
    'countdowns': await n(db.countdowns),
    'focus_sessions': await n(db.focusSessions),
    'folders': await n(db.folders),
    'notes': await n(db.notes),
    'note_links': await n(db.noteLinks),
  };
}

void main() {
  test('export/import round-trip preserves rows', () async {
    final db1 = _db();
    addTearDown(db1.close);
    await _seed(db1);
    final before = await _counts(db1);

    final service1 = BackupService(db1);
    final raw = service1.encode(await service1.exportJson());

    final db2 = _db();
    addTearDown(db2.close);
    final service2 = BackupService(db2);
    await service2.restoreJson(service2.decode(raw));
    expect(await _counts(db2), before);

    final habit = await (db2.select(
      db2.habits,
    )..where((h) => h.name.equals('Read'))).getSingle();
    expect(habit.sectionId, isNotNull);
    final log = await (db2.select(
      db2.habitLogs,
    )..where((l) => l.habitId.equals(habit.id))).getSingle();
    expect(log.done, isTrue);
    final countdown = await (db2.select(
      db2.countdowns,
    )..where((c) => c.title.equals('Trip'))).getSingle();
    expect(countdown.showAge, isTrue);
    final session = await db2.select(db2.focusSessions).getSingle();
    expect(session.note, 'deep work');
    final note = await (db2.select(
      db2.notes,
    )..where((t) => t.id.equals('n1'))).getSingle();
    expect(note.body, 'milk and eggs');
    final task = await (db2.select(
      db2.tasks,
    )..where((t) => t.id.equals('task1'))).getSingle();
    expect(task.title, 'Buy milk');
    final event = await (db2.select(
      db2.events,
    )..where((e) => e.id.equals('event1'))).getSingle();
    expect(event.title, 'Dentist');
  });

  test('restore rejects bad input with typed errors', () async {
    final db = _db();
    addTearDown(db.close);
    final service = BackupService(db);
    expect(
      () => service.decode('[1,2]'),
      throwsA(isA<BackupFormatException>()),
    );
    expect(
      () => service.restoreJson({'version': 999, 'tables': {}}),
      throwsA(isA<BackupFormatException>()),
    );
    expect(
      () => service.restoreJson({'version': 1, 'tables': []}),
      throwsA(isA<BackupFormatException>()),
    );
    expect(
      () => service.restoreJson({
        'version': 1,
        'tables': {
          'habits': [
            {'name': 'missing id'},
          ],
        },
      }),
      throwsA(isA<BackupFormatException>()),
    );
    // Failed restore leaves existing rows untouched.
    await HabitRepository(db).createHabit(name: 'Keep');
    expect(
      () => service.restoreJson({
        'version': 1,
        'tables': {
          'habits': [
            {'id': 'x'},
          ],
        },
      }),
      throwsA(isA<BackupFormatException>()),
    );
    expect(await db.select(db.habits).get(), hasLength(1));
  });
}

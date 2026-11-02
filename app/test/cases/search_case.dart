// Global search suite: per-repo search hits, empty queries,
// wildcard safety.
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/countdown_repository.dart';
import 'package:ephemeron/data/repositories/event_repository.dart';
import 'package:ephemeron/data/repositories/habit_repository.dart';
import 'package:ephemeron/data/repositories/note_repository.dart';
import 'package:ephemeron/data/repositories/occurrence_repository.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<void> _seed(AppDatabase db) async {
  const now = 1700000000000;
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
  await EventRepository(db, OccurrenceRepository(db)).createEvent(
    calendarId: 'cal1',
    title: 'Dentist appointment',
    location: 'Downtown clinic',
  );
  final tasks = TaskRepository(db);
  final listId = await tasks.createList('Inbox');
  final taskId = await tasks.createTask(listId: listId, title: 'Buy milk');
  await tasks.setTaskTags(taskId, ['groceries']);
  await NoteRepository(db).createNote(title: 'Shopping', body: 'milk and eggs');
  await HabitRepository(db).createHabit(name: 'Read daily');
  await CountdownRepository(
    db,
  ).createCountdown(title: 'Trip to beach', targetDate: '2027-06-01');
}

void main() {
  test('search finds rows across entities', () async {
    final db = _db();
    addTearDown(db.close);
    await _seed(db);
    final tasks = TaskRepository(db);
    expect(
      (await tasks.searchTasks('milk')).map((t) => t.title),
      contains('Buy milk'),
    );
    expect(await tasks.searchTasks('dentist'), isEmpty);
    expect(
      (await tasks.searchTags('groc')).map((t) => t.name),
      contains('groceries'),
    );
    expect(
      (await EventRepository(
        db,
        OccurrenceRepository(db),
      ).searchEvents('clinic')).map((e) => e.title),
      contains('Dentist appointment'),
    );
    expect(
      (await NoteRepository(db).searchNotes('eggs')).map((h) => h.note.title),
      contains('Shopping'),
    );
    expect(
      (await HabitRepository(db).searchHabits('read')).map((h) => h.name),
      contains('Read daily'),
    );
    expect(
      (await CountdownRepository(
        db,
      ).searchCountdowns('beach')).map((c) => c.title),
      contains('Trip to beach'),
    );
  });

  test('empty queries and wildcards are safe', () async {
    final db = _db();
    addTearDown(db.close);
    await _seed(db);
    final tasks = TaskRepository(db);
    expect(await tasks.searchTasks(''), isEmpty);
    expect(await tasks.searchTasks('   '), isEmpty);
    // Literal % must not match everything.
    expect(await tasks.searchTasks('%'), isEmpty);
    expect(await HabitRepository(db).searchHabits('%'), isEmpty);
  });
}

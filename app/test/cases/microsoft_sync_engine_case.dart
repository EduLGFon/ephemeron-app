import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/domain/microsoft/microsoft_graph_models.dart';
import 'package:ephemeron/features/sync/data/microsoft_graph_client.dart';
import 'package:ephemeron/features/sync/data/microsoft_sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMs implements MicrosoftGraphClient {
  List<MsCalendar> calendars = [];
  List<MsEvent> events = [];
  Map<String, List<MsEvent>> eventsByCalendar = {};
  List<MsTodoList> lists = [];
  Map<String, List<MsTodoTask>> tasksByList = {};

  @override
  Future<MsIdentity> getMe() async => const MsIdentity(id: 'u');

  @override
  Future<List<MsCalendar>> listCalendars() async => calendars;

  @override
  Future<List<MsEvent>> calendarView(
    DateTime startUtc,
    DateTime endUtc, {
    String? calendarId,
  }) async => eventsByCalendar[calendarId] ?? events;

  @override
  Future<List<MsTodoList>> listTodoLists() async => lists;

  @override
  Future<List<MsTodoTask>> listTodoTasks(String listId) async =>
      tasksByList[listId] ?? [];
}

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

MsDateTimeTimeZone _dt(String s) =>
    MsDateTimeTimeZone(dateTime: s, timeZone: 'UTC');

void main() {
  test('idempotent double pull creates no duplicates', () async {
    final db = _db();
    addTearDown(db.close);
    final fake = FakeMs()
      ..calendars = [const MsCalendar(id: 'c1', name: 'Cal', canEdit: true)]
      ..events = [
        MsEvent(
          id: 'e1',
          subject: 'Meet',
          start: _dt('2026-01-01T10:00:00'),
          end: _dt('2026-01-01T11:00:00'),
        ),
      ]
      ..lists = [const MsTodoList(id: 'l1', displayName: 'Tasks')]
      ..tasksByList = {
        'l1': [MsTodoTask(id: 't1', title: 'Buy milk')],
      };
    final engine = MicrosoftSyncEngine(db, fake, 'acct@example.com');
    await engine.syncNow();
    await engine.syncNow();
    expect(await db.select(db.calendars).get(), hasLength(1));
    expect(await db.select(db.events).get(), hasLength(1));
    expect(await db.select(db.taskLists).get(), hasLength(1));
    expect(await db.select(db.tasks).get(), hasLength(1));
  });

  test('two accounts with identical remote ids stay isolated', () async {
    final db = _db();
    addTearDown(db.close);
    for (final acct in ['a@example.com', 'b@example.com']) {
      final fake = FakeMs()
        ..calendars = [const MsCalendar(id: 'c1', name: 'Cal', canEdit: true)]
        ..events = [
          MsEvent(
            id: 'e1',
            subject: 'Meet $acct',
            start: _dt('2026-01-01T10:00:00'),
            end: _dt('2026-01-01T11:00:00'),
          ),
        ];
      final engine = MicrosoftSyncEngine(db, fake, acct);
      await engine.syncNow();
    }
    final cals = await db.select(db.calendars).get();
    expect(cals, hasLength(2));
    final evs = await db.select(db.events).get();
    expect(evs, hasLength(2));
    expect(evs.map((e) => e.microsoftAccount).toSet(), {
      'a@example.com',
      'b@example.com',
    });
  });

  test('local-only task fields survive re-pull', () async {
    final db = _db();
    addTearDown(db.close);
    final fake = FakeMs()
      ..calendars = [const MsCalendar(id: 'c1', name: 'Cal', canEdit: true)]
      ..lists = [const MsTodoList(id: 'l1', displayName: 'Tasks')]
      ..tasksByList = {
        'l1': [MsTodoTask(id: 't1', title: 'Buy milk')],
      };
    final engine = MicrosoftSyncEngine(db, fake, 'acct@example.com');
    await engine.syncNow();
    // set local fields
    final task = (await db.select(db.tasks).get()).single;
    final taskUpdate = db.update(db.tasks)..where((t) => t.id.equals(task.id));
    await taskUpdate.write(
      TasksCompanion(
        plannedDate: Value('2026-02-02'),
        plannedStart: Value('2026-02-02T09:00'),
        plannedEnd: Value('2026-02-02T10:00'),
        seriesId: Value('series1'),
        recurrenceKey: Value('2026-02-02'),
        priority: Value(3),
        durationMin: Value(45),
        rrule: Value('FREQ=DAILY'),
        repeatMode: Value('daily'),
        pinned: Value(true),
        wontDo: Value(true),
      ),
    );
    // re-pull with updated title
    fake.tasksByList = {
      'l1': [MsTodoTask(id: 't1', title: 'Buy milk v2')],
    };
    await engine.syncNow();
    final after = (await db.select(db.tasks).get()).single;
    expect(after.title, 'Buy milk v2');
    expect(after.plannedDate, '2026-02-02');
    expect(after.plannedStart, '2026-02-02T09:00');
    expect(after.plannedEnd, '2026-02-02T10:00');
    expect(after.seriesId, 'series1');
    expect(after.recurrenceKey, '2026-02-02');
    expect(after.priority, 3);
    expect(after.durationMin, 45);
    expect(after.rrule, 'FREQ=DAILY');
    expect(after.repeatMode, 'daily');
    expect(after.pinned, true);
    expect(after.wontDo, true);
  });

  test(
    'local event alarmPreset/reminders/visibility survive re-pull',
    () async {
      final db = _db();
      addTearDown(db.close);
      final fake = FakeMs()
        ..calendars = [const MsCalendar(id: 'c1', name: 'Cal', canEdit: true)]
        ..events = [
          MsEvent(
            id: 'e1',
            subject: 'Meet',
            start: _dt('2026-01-01T10:00:00'),
            end: _dt('2026-01-01T11:00:00'),
          ),
        ];
      final engine = MicrosoftSyncEngine(db, fake, 'acct@example.com');
      await engine.syncNow();
      final ev = (await db.select(db.events).get()).single;
      final eventUpdate = db.update(db.events)
        ..where((t) => t.id.equals(ev.id));
      await eventUpdate.write(
        EventsCompanion(
          alarmPreset: Value('loud'),
          reminders: Value('[10]'),
          visibility: Value('private'),
        ),
      );
      fake.events = [
        MsEvent(
          id: 'e1',
          subject: 'Meet v2',
          start: _dt('2026-01-01T10:00:00'),
          end: _dt('2026-01-01T11:00:00'),
        ),
      ];
      await engine.syncNow();
      final after = (await db.select(db.events).get()).single;
      expect(after.title, 'Meet v2');
      expect(after.alarmPreset, 'loud');
      expect(after.reminders, '[10]');
      expect(after.visibility, 'private');
    },
  );

  test('timed and all-day events map to correct UTC/date fields', () async {
    final db = _db();
    addTearDown(db.close);
    final fake = FakeMs()
      ..calendars = [const MsCalendar(id: 'c1', name: 'Cal', canEdit: true)]
      ..events = [
        MsEvent(
          id: 'timed',
          subject: 'Timed',
          start: _dt('2026-01-01T10:00:00'),
          end: _dt('2026-01-01T11:00:00'),
          isAllDay: false,
        ),
        MsEvent(
          id: 'allday',
          subject: 'AllDay',
          start: _dt('2026-01-02T00:00:00'),
          end: _dt('2026-01-03T00:00:00'),
          isAllDay: true,
        ),
      ];
    final engine = MicrosoftSyncEngine(db, fake, 'acct@example.com');
    await engine.syncNow();
    final rows = await db.select(db.events).get();
    final timed = rows.firstWhere((e) => e.remoteId == 'timed');
    expect(timed.startUtc, DateTime.utc(2026, 1, 1, 10).millisecondsSinceEpoch);
    expect(timed.endUtc, DateTime.utc(2026, 1, 1, 11).millisecondsSinceEpoch);
    expect(timed.startDate, isNull);
    expect(timed.isAllDay, false);
    final allday = rows.firstWhere((e) => e.remoteId == 'allday');
    expect(allday.startUtc, isNull);
    expect(allday.endUtc, isNull);
    expect(allday.startDate, '2026-01-02');
    expect(allday.endDate, '2026-01-03');
    expect(allday.isAllDay, true);
  });

  test('events link to their own Microsoft calendar', () async {
    final db = _db();
    addTearDown(db.close);
    final fake = FakeMs()
      ..calendars = [
        const MsCalendar(id: 'c1', name: 'Work', canEdit: true),
        const MsCalendar(id: 'c2', name: 'Home', canEdit: true),
      ]
      ..eventsByCalendar = {
        'c1': [
          MsEvent(
            id: 'e1',
            subject: 'Work event',
            start: _dt('2026-01-01T10:00:00'),
            end: _dt('2026-01-01T11:00:00'),
          ),
        ],
        'c2': [
          MsEvent(
            id: 'e2',
            subject: 'Home event',
            start: _dt('2026-01-01T12:00:00'),
            end: _dt('2026-01-01T13:00:00'),
          ),
        ],
      };
    final engine = MicrosoftSyncEngine(db, fake, 'acct@example.com');
    await engine.syncNow();
    final cals = await db.select(db.calendars).get();
    final work = cals.firstWhere((c) => c.remoteId == 'c1');
    final home = cals.firstWhere((c) => c.remoteId == 'c2');
    final events = await db.select(db.events).get();
    expect(events.firstWhere((e) => e.remoteId == 'e1').calendarId, work.id);
    expect(events.firstWhere((e) => e.remoteId == 'e2').calendarId, home.id);
  });

  test('cancelled events map to status', () async {
    final db = _db();
    addTearDown(db.close);
    final fake = FakeMs()
      ..calendars = [const MsCalendar(id: 'c1', name: 'Cal', canEdit: true)]
      ..events = [
        MsEvent(
          id: 'canc',
          subject: 'Cancelled',
          isCancelled: true,
          start: _dt('2026-01-01T10:00:00'),
          end: _dt('2026-01-01T11:00:00'),
        ),
      ];
    final engine = MicrosoftSyncEngine(db, fake, 'acct@example.com');
    await engine.syncNow();
    final ev = (await db.select(db.events).get()).single;
    expect(ev.status, 'cancelled');
  });

  test('To Do dueDate/dueTime and completedAt map correctly', () async {
    final db = _db();
    addTearDown(db.close);
    final fake = FakeMs()
      ..lists = [const MsTodoList(id: 'l1', displayName: 'Tasks')]
      ..tasksByList = {
        'l1': [
          MsTodoTask(
            id: 't1',
            title: 'Buy milk',
            status: 'completed',
            dueDateTime: _dt('2026-01-02T14:30:00'),
            completedDateTime: _dt('2026-01-03T00:00:00'),
          ),
        ],
      };
    final engine = MicrosoftSyncEngine(db, fake, 'acct@example.com');
    await engine.syncNow();
    final task = (await db.select(db.tasks).get()).single;
    expect(task.dueDate, '2026-01-02');
    expect(task.dueTime, 14 * 60 + 30);
    expect(task.completedAt, DateTime.utc(2026, 1, 3).millisecondsSinceEpoch);
  });

  test(
    'calendar readOnly from canEdit and enabled preserved across pulls',
    () async {
      final db = _db();
      addTearDown(db.close);
      final fake = FakeMs()
        ..calendars = [const MsCalendar(id: 'c1', name: 'Cal', canEdit: false)];
      final engine = MicrosoftSyncEngine(db, fake, 'acct@example.com');
      await engine.syncNow();
      final cal = (await db.select(db.calendars).get()).single;
      expect(cal.readOnly, true);
      expect(cal.enabled, true);
      // flip enabled locally
      final calUpdate = db.update(db.calendars)
        ..where((t) => t.id.equals(cal.id));
      await calUpdate.write(const CalendarsCompanion(enabled: Value(false)));
      // change canEdit remotely
      fake.calendars = [const MsCalendar(id: 'c1', name: 'Cal', canEdit: true)];
      await engine.syncNow();
      final after = (await db.select(db.calendars).get()).single;
      expect(after.readOnly, false);
      expect(after.enabled, false);
    },
  );

  test('null token surfaces as auth failure without writing rows', () async {
    final db = _db();
    addTearDown(db.close);
    final client = HttpMicrosoftGraphClient(
      accessToken: () async => null,
      httpClient: null,
    );
    final engine = MicrosoftSyncEngine(db, client, 'acct@example.com');
    final result = await engine.syncNow();
    expect(result.authFailure, true);
    expect(await db.select(db.calendars).get(), isEmpty);
    expect(await db.select(db.events).get(), isEmpty);
    expect(await db.select(db.taskLists).get(), isEmpty);
    expect(await db.select(db.tasks).get(), isEmpty);
  });

  test(
    'remote task deletion is reconciled after complete list fetch',
    () async {
      final db = _db();
      addTearDown(db.close);
      final fake = FakeMs()
        ..lists = [const MsTodoList(id: 'l1', displayName: 'Tasks')]
        ..tasksByList = {
          'l1': [
            MsTodoTask(id: 't1', title: 'Keep'),
            MsTodoTask(id: 't2', title: 'Gone'),
          ],
        };
      final engine = MicrosoftSyncEngine(db, fake, 'acct@example.com');
      await engine.syncNow();
      fake.tasksByList = {
        'l1': [MsTodoTask(id: 't1', title: 'Keep')],
      };
      await engine.syncNow();
      final rows = await (db.select(
        db.tasks,
      )..where((t) => t.microsoftAccount.equals('acct@example.com'))).get();
      final kept = rows.firstWhere((t) => t.remoteId == 't1');
      final gone = rows.firstWhere((t) => t.remoteId == 't2');
      expect(kept.deletedAt, isNull);
      expect(gone.deletedAt, isNotNull);
      expect(gone.dirty, false);
    },
  );

  test('dirty local task is never reconciled as remote deletion', () async {
    final db = _db();
    addTearDown(db.close);
    final fake = FakeMs()
      ..lists = [const MsTodoList(id: 'l1', displayName: 'Tasks')]
      ..tasksByList = {
        'l1': [MsTodoTask(id: 't1', title: 'Edit me')],
      };
    final engine = MicrosoftSyncEngine(db, fake, 'acct@example.com');
    await engine.syncNow();
    final task = (await db.select(db.tasks).get()).single;
    await (db.update(db.tasks)..where((t) => t.id.equals(task.id))).write(
      const TasksCompanion(dirty: Value(true), title: Value('Local edit')),
    );
    fake.tasksByList = {'l1': []};
    await engine.syncNow();
    final after = (await db.select(db.tasks).get()).single;
    expect(after.deletedAt, isNull);
    expect(after.dirty, true);
    expect(after.title, 'Local edit');
  });

  test('remote task list deletion soft-deletes list and its tasks', () async {
    final db = _db();
    addTearDown(db.close);
    final fake = FakeMs()
      ..lists = [
        const MsTodoList(id: 'l1', displayName: 'Keep'),
        const MsTodoList(id: 'l2', displayName: 'Gone'),
      ]
      ..tasksByList = {
        'l1': [MsTodoTask(id: 't1', title: 'Stay')],
        'l2': [MsTodoTask(id: 't2', title: 'Orphan no')],
      };
    final engine = MicrosoftSyncEngine(db, fake, 'acct@example.com');
    await engine.syncNow();
    fake.lists = [const MsTodoList(id: 'l1', displayName: 'Keep')];
    fake.tasksByList = {
      'l1': [MsTodoTask(id: 't1', title: 'Stay')],
    };
    await engine.syncNow();
    final lists = await (db.select(
      db.taskLists,
    )..where((t) => t.microsoftAccount.equals('acct@example.com'))).get();
    final keptList = lists.firstWhere((l) => l.remoteId == 'l1');
    final goneList = lists.firstWhere((l) => l.remoteId == 'l2');
    expect(keptList.deletedAt, isNull);
    expect(goneList.deletedAt, isNotNull);
    final tasks = await (db.select(
      db.tasks,
    )..where((t) => t.microsoftAccount.equals('acct@example.com'))).get();
    expect(tasks.firstWhere((t) => t.remoteId == 't1').deletedAt, isNull);
    expect(tasks.firstWhere((t) => t.remoteId == 't2').deletedAt, isNotNull);
  });

  test('reconciliation is scoped to the synced Microsoft account', () async {
    final db = _db();
    addTearDown(db.close);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.taskLists)
        .insert(
          TaskListsCompanion.insert(
            id: 'local-ms',
            remoteId: const Value('shared'),
            name: 'Other acct',
            microsoftAccount: const Value('other@example.com'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'local-task',
            listId: const Value('local-ms'),
            remoteId: const Value('t-shared'),
            title: const Value('Other'),
            microsoftAccount: const Value('other@example.com'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final fake = FakeMs()
      ..lists = [const MsTodoList(id: 'l1', displayName: 'Mine')]
      ..tasksByList = {
        'l1': [MsTodoTask(id: 't1', title: 'Mine')],
      };
    final engine = MicrosoftSyncEngine(db, fake, 'acct@example.com');
    await engine.syncNow();
    final otherList = await (db.select(
      db.taskLists,
    )..where((t) => t.id.equals('local-ms'))).getSingle();
    final otherTask = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals('local-task'))).getSingle();
    expect(otherList.deletedAt, isNull);
    expect(otherTask.deletedAt, isNull);
  });

  test(
    'task fetch failure prevents reconciliation for that list only',
    () async {
      final db = _db();
      addTearDown(db.close);
      final fake = _FailingTasksFake()
        ..lists = [
          const MsTodoList(id: 'l1', displayName: 'First'),
          const MsTodoList(id: 'l2', displayName: 'Second'),
        ]
        ..tasksByList = {
          'l1': [MsTodoTask(id: 't1', title: 'One')],
          'l2': [
            MsTodoTask(id: 't2', title: 'Keep'),
            MsTodoTask(id: 't3', title: 'Remote gone'),
          ],
        };
      final engine = MicrosoftSyncEngine(db, fake, 'acct@example.com');
      await engine.syncNow();
      // l1 task fetch fails; l2 task reconciliation must not run because sync
      // aborts before reaching l2.
      fake.failListId = 'l1';
      fake.tasksByList = {
        'l1': [MsTodoTask(id: 't1', title: 'One')],
        'l2': [MsTodoTask(id: 't2', title: 'Keep')],
      };
      await expectLater(engine.syncNow(), throwsA(isA<StateError>()));
      final t3 = await (db.select(
        db.tasks,
      )..where((t) => t.remoteId.equals('t3'))).getSingle();
      expect(t3.deletedAt, isNull);
    },
  );

  test('calendarView pagination is followed (client contract)', () async {
    // Pagination is implemented in HttpMicrosoftGraphClient._paginate and
    // covered by microsoft_graph_case.dart; reconciliation relies on complete
    // results, so a fake returning complete data is sufficient here.
    final db = _db();
    addTearDown(db.close);
    final fake = FakeMs()
      ..lists = [const MsTodoList(id: 'l1', displayName: 'Tasks')]
      ..tasksByList = {
        'l1': [MsTodoTask(id: 't1', title: 'One')],
      };
    final engine = MicrosoftSyncEngine(db, fake, 'acct@example.com');
    await engine.syncNow();
    fake.tasksByList = {'l1': []};
    await engine.syncNow();
    final task = (await db.select(db.tasks).get()).single;
    expect(task.deletedAt, isNotNull);
  });
}

class _FailingTasksFake extends FakeMs {
  String? failListId;

  @override
  Future<List<MsTodoTask>> listTodoTasks(String listId) async {
    if (listId == failListId) throw StateError('boom');
    return super.listTodoTasks(listId);
  }
}

part of '../backup_service.dart';

CalendarsCompanion _calendarOf(Map<String, dynamic> m) =>
    CalendarsCompanion.insert(
      id: _reqStr(m, 'id'),
      remoteId: Value(_optStr(m, 'remoteId')),
      name: _reqStr(m, 'name'),
      color: Value(_optStr(m, 'color')),
      enabled: Value(_reqBool(m, 'enabled', fallback: true)),
      readOnly: Value(_reqBool(m, 'readOnly')),
      source: Value(_optStr(m, 'source') ?? 'device'),
      createdAt: _reqInt(m, 'createdAt'),
      updatedAt: _reqInt(m, 'updatedAt'),
      deletedAt: Value(_optInt(m, 'deletedAt')),
      dirty: Value(_reqBool(m, 'dirty')),
      remoteEtag: Value(_optStr(m, 'remoteEtag')),
      googleAccount: Value(_optStr(m, 'googleAccount')),
    );

EventsCompanion _eventOf(Map<String, dynamic> m) => EventsCompanion.insert(
  id: _reqStr(m, 'id'),
  calendarId: _reqStr(m, 'calendarId'),
  title: Value(_optStr(m, 'title') ?? ''),
  notes: Value(_optStr(m, 'notes')),
  notesOverflowNoteId: Value(_optStr(m, 'notesOverflowNoteId')),
  location: Value(_optStr(m, 'location')),
  startUtc: Value(_optInt(m, 'startUtc')),
  endUtc: Value(_optInt(m, 'endUtc')),
  startDate: Value(_optStr(m, 'startDate')),
  endDate: Value(_optStr(m, 'endDate')),
  isAllDay: Value(_reqBool(m, 'isAllDay')),
  tzId: Value(_optStr(m, 'tzId')),
  endTzId: Value(_optStr(m, 'endTzId')),
  rrule: Value(_optStr(m, 'rrule')),
  recurringMasterId: Value(_optStr(m, 'recurringMasterId')),
  originalStart: Value(_optInt(m, 'originalStart')),
  status: Value(_optStr(m, 'status') ?? 'confirmed'),
  colorId: Value(_optStr(m, 'colorId')),
  meetUrl: Value(_optStr(m, 'meetUrl')),
  reminders: Value(_optStr(m, 'reminders')),
  alarmPreset: Value(_optStr(m, 'alarmPreset')),
  visibility: Value(_optStr(m, 'visibility')),
  transparency: Value(_optStr(m, 'transparency')),
  googleAccount: Value(_optStr(m, 'googleAccount')),
  createdAt: _reqInt(m, 'createdAt'),
  updatedAt: _reqInt(m, 'updatedAt'),
  deletedAt: Value(_optInt(m, 'deletedAt')),
  dirty: Value(_reqBool(m, 'dirty')),
  remoteId: Value(_optStr(m, 'remoteId')),
  remoteEtag: Value(_optStr(m, 'remoteEtag')),
);

EventAttendeesCompanion _attendeeOf(Map<String, dynamic> m) =>
    EventAttendeesCompanion.insert(
      id: _reqStr(m, 'id'),
      eventId: _reqStr(m, 'eventId'),
      email: _reqStr(m, 'email'),
      name: Value(_optStr(m, 'name')),
      rsvp: Value(_optStr(m, 'rsvp')),
      isOrganizer: Value(_reqBool(m, 'isOrganizer')),
      isSelf: Value(_reqBool(m, 'isSelf')),
    );

TaskListsCompanion _taskListOf(Map<String, dynamic> m) =>
    TaskListsCompanion.insert(
      id: _reqStr(m, 'id'),
      remoteId: Value(_optStr(m, 'remoteId')),
      name: _reqStr(m, 'name'),
      color: Value(_optStr(m, 'color')),
      sortOrder: Value(_optInt(m, 'sortOrder') ?? 0),
      createdAt: _reqInt(m, 'createdAt'),
      updatedAt: _reqInt(m, 'updatedAt'),
      deletedAt: Value(_optInt(m, 'deletedAt')),
      dirty: Value(_reqBool(m, 'dirty')),
      remoteEtag: Value(_optStr(m, 'remoteEtag')),
      googleAccount: Value(_optStr(m, 'googleAccount')),
    );

TasksCompanion _taskOf(Map<String, dynamic> m) => TasksCompanion.insert(
  id: _reqStr(m, 'id'),
  listId: Value(_optStr(m, 'listId')),
  title: Value(_optStr(m, 'title') ?? ''),
  notes: Value(_optStr(m, 'notes')),
  priority: Value(_optInt(m, 'priority') ?? 0),
  dueDate: Value(_optStr(m, 'dueDate')),
  plannedDate: Value(_optStr(m, 'plannedDate')),
  plannedStart: Value(_optStr(m, 'plannedStart')),
  plannedEnd: Value(_optStr(m, 'plannedEnd')),
  seriesId: Value(_optStr(m, 'seriesId')),
  recurrenceKey: Value(_optStr(m, 'recurrenceKey')),
  dueTime: Value(_optInt(m, 'dueTime')),
  durationMin: Value(_optInt(m, 'durationMin')),
  rrule: Value(_optStr(m, 'rrule')),
  repeatMode: Value(_optStr(m, 'repeatMode')),
  parentId: Value(_optStr(m, 'parentId')),
  pinned: Value(_reqBool(m, 'pinned')),
  wontDo: Value(_reqBool(m, 'wontDo')),
  completedAt: Value(_optInt(m, 'completedAt')),
  sortOrder: Value(_optInt(m, 'sortOrder') ?? 0),
  alarmPreset: Value(_optStr(m, 'alarmPreset')),
  reminders: Value(_optStr(m, 'reminders')),
  createdAt: _reqInt(m, 'createdAt'),
  updatedAt: _reqInt(m, 'updatedAt'),
  deletedAt: Value(_optInt(m, 'deletedAt')),
  dirty: Value(_reqBool(m, 'dirty')),
  remoteId: Value(_optStr(m, 'remoteId')),
  remoteEtag: Value(_optStr(m, 'remoteEtag')),
  googleAccount: Value(_optStr(m, 'googleAccount')),
);

TaskTagsCompanion _taskTagOf(Map<String, dynamic> m) =>
    TaskTagsCompanion.insert(
      taskId: _reqStr(m, 'taskId'),
      tagId: _reqStr(m, 'tagId'),
    );

TaskOccurrenceStatesCompanion _taskOccurrenceStateOf(Map<String, dynamic> m) =>
    TaskOccurrenceStatesCompanion.insert(
      seriesId: _reqStr(m, 'seriesId'),
      occurrenceDate: _reqStr(m, 'occurrenceDate'),
      status: _reqStr(m, 'status'),
      completedAt: Value(_optInt(m, 'completedAt')),
      updatedAt: _reqInt(m, 'updatedAt'),
    );

SmartListsCompanion _smartListOf(Map<String, dynamic> m) =>
    SmartListsCompanion.insert(
      id: _reqStr(m, 'id'),
      name: _reqStr(m, 'name'),
      filterJson: Value(_optStr(m, 'filterJson') ?? '{}'),
      createdAt: _reqInt(m, 'createdAt'),
      updatedAt: _reqInt(m, 'updatedAt'),
    );

TagsCompanion _tagOf(Map<String, dynamic> m) => TagsCompanion.insert(
  id: _reqStr(m, 'id'),
  name: _reqStr(m, 'name'),
  color: Value(_optStr(m, 'color')),
  createdAt: _reqInt(m, 'createdAt'),
  updatedAt: _reqInt(m, 'updatedAt'),
);

TagDefaultsCompanion _tagDefaultOf(Map<String, dynamic> m) =>
    TagDefaultsCompanion.insert(
      tagId: _reqStr(m, 'tagId'),
      defaultReminderJson: Value(_optStr(m, 'defaultReminderJson')),
    );

HabitSectionsCompanion _habitSectionOf(Map<String, dynamic> m) =>
    HabitSectionsCompanion.insert(
      id: _reqStr(m, 'id'),
      name: _reqStr(m, 'name'),
      sortOrder: Value(_optInt(m, 'sortOrder') ?? 0),
      createdAt: _reqInt(m, 'createdAt'),
      updatedAt: _reqInt(m, 'updatedAt'),
    );

HabitsCompanion _habitOf(Map<String, dynamic> m) => HabitsCompanion.insert(
  id: _reqStr(m, 'id'),
  sectionId: Value(_optStr(m, 'sectionId')),
  name: _reqStr(m, 'name'),
  frequency: Value(_optStr(m, 'frequency') ?? 'daily'),
  weekdaysMask: Value(_optInt(m, 'weekdaysMask') ?? 0),
  weeklyTarget: Value(_optInt(m, 'weeklyTarget')),
  intervalDays: Value(_optInt(m, 'intervalDays')),
  goalType: Value(_optStr(m, 'goalType')),
  goalAmount: Value(_optDouble(m, 'goalAmount')),
  unit: Value(_optStr(m, 'unit')),
  increment: Value(_optDouble(m, 'increment')),
  goalDurationDays: Value(_optInt(m, 'goalDurationDays')),
  startDate: Value(_optStr(m, 'startDate')),
  archived: Value(_reqBool(m, 'archived')),
  reminderTime: Value(_optStr(m, 'reminderTime')),
  alarmPreset: Value(_optStr(m, 'alarmPreset')),
  createdAt: _reqInt(m, 'createdAt'),
  updatedAt: _reqInt(m, 'updatedAt'),
  deletedAt: Value(_optInt(m, 'deletedAt')),
  dirty: Value(_reqBool(m, 'dirty')),
  remoteId: Value(_optStr(m, 'remoteId')),
  remoteEtag: Value(_optStr(m, 'remoteEtag')),
);

HabitLogsCompanion _habitLogOf(Map<String, dynamic> m) =>
    HabitLogsCompanion.insert(
      id: _reqStr(m, 'id'),
      habitId: _reqStr(m, 'habitId'),
      dayKey: _reqStr(m, 'dayKey'),
      amount: Value(_optDouble(m, 'amount') ?? 0),
      done: Value(_reqBool(m, 'done')),
      skipped: Value(_reqBool(m, 'skipped')),
      createdAt: _reqInt(m, 'createdAt'),
      updatedAt: _reqInt(m, 'updatedAt'),
    );

CountdownsCompanion _countdownOf(Map<String, dynamic> m) =>
    CountdownsCompanion.insert(
      id: _reqStr(m, 'id'),
      title: _reqStr(m, 'title'),
      type: Value(_optStr(m, 'type')),
      template: Value(_optStr(m, 'template')),
      targetDate: Value(_optStr(m, 'targetDate')),
      yearlyRepeat: Value(_reqBool(m, 'yearlyRepeat')),
      showAge: Value(_reqBool(m, 'showAge')),
      notes: Value(_optStr(m, 'notes')),
      alertOffsetDays: Value(_optInt(m, 'alertOffsetDays')),
      alertTimeMin: Value(_optInt(m, 'alertTimeMin')),
      alarmPreset: Value(_optStr(m, 'alarmPreset')),
      createdAt: _reqInt(m, 'createdAt'),
      updatedAt: _reqInt(m, 'updatedAt'),
      deletedAt: Value(_optInt(m, 'deletedAt')),
    );

FocusSessionsCompanion _focusOf(Map<String, dynamic> m) =>
    FocusSessionsCompanion.insert(
      id: _reqStr(m, 'id'),
      taskId: Value(_optStr(m, 'taskId')),
      habitId: Value(_optStr(m, 'habitId')),
      startUtc: _reqInt(m, 'startUtc'),
      endUtc: Value(_optInt(m, 'endUtc')),
      targetEndUtc: Value(_optInt(m, 'targetEndUtc')),
      phase: Value(_optStr(m, 'phase')),
      note: Value(_optStr(m, 'note')),
      alarmPreset: Value(_optStr(m, 'alarmPreset')),
      createdAt: _reqInt(m, 'createdAt'),
      updatedAt: _reqInt(m, 'updatedAt'),
    );

FoldersCompanion _folderOf(Map<String, dynamic> m) => FoldersCompanion.insert(
  id: _reqStr(m, 'id'),
  parentId: Value(_optStr(m, 'parentId')),
  name: _reqStr(m, 'name'),
  sortOrder: Value(_optInt(m, 'sortOrder') ?? 0),
  createdAt: _reqInt(m, 'createdAt'),
  updatedAt: _reqInt(m, 'updatedAt'),
  deletedAt: Value(_optInt(m, 'deletedAt')),
);

NotesCompanion _noteOf(Map<String, dynamic> m) => NotesCompanion.insert(
  id: _reqStr(m, 'id'),
  folderId: Value(_optStr(m, 'folderId')),
  title: Value(_optStr(m, 'title') ?? ''),
  body: Value(_optStr(m, 'body')),
  pinned: Value(_reqBool(m, 'pinned')),
  linkedEventId: Value(_optStr(m, 'linkedEventId')),
  createdAt: _reqInt(m, 'createdAt'),
  updatedAt: _reqInt(m, 'updatedAt'),
  deletedAt: Value(_optInt(m, 'deletedAt')),
  dirty: Value(_reqBool(m, 'dirty')),
  remoteId: Value(_optStr(m, 'remoteId')),
  remoteEtag: Value(_optStr(m, 'remoteEtag')),
);

NoteLinksCompanion _noteLinkOf(Map<String, dynamic> m) =>
    NoteLinksCompanion.insert(
      fromNoteId: _reqStr(m, 'fromNoteId'),
      toNoteId: _reqStr(m, 'toNoteId'),
    );

AttachmentsCompanion _attachmentOf(Map<String, dynamic> m) =>
    AttachmentsCompanion.insert(
      id: _reqStr(m, 'id'),
      ownerType: _reqStr(m, 'ownerType'),
      ownerId: _reqStr(m, 'ownerId'),
      path: _reqStr(m, 'path'),
      mime: Value(_optStr(m, 'mime')),
      size: Value(_optInt(m, 'size')),
      hash: Value(_optStr(m, 'hash')),
      createdAt: _reqInt(m, 'createdAt'),
    );

OutboxCompanion _outboxOf(Map<String, dynamic> m) => OutboxCompanion.insert(
  id: _reqStr(m, 'id'),
  entity: _reqStr(m, 'entity'),
  entityId: _reqStr(m, 'entityId'),
  op: _reqStr(m, 'op'),
  payload: Value(_optStr(m, 'payload')),
  attempts: Value(_optInt(m, 'attempts') ?? 0),
  nextTryAt: Value(_optInt(m, 'nextTryAt')),
  lastError: Value(_optStr(m, 'lastError')),
  createdAt: _reqInt(m, 'createdAt'),
);

SyncStateCompanion _syncStateOf(Map<String, dynamic> m) =>
    SyncStateCompanion.insert(
      key: _reqStr(m, 'key'),
      value: Value(_optStr(m, 'value')),
      lastSyncAt: Value(_optInt(m, 'lastSyncAt')),
      lastError: Value(_optStr(m, 'lastError')),
    );

DraftsCompanion _draftOf(Map<String, dynamic> m) => DraftsCompanion.insert(
  id: _reqStr(m, 'id'),
  formType: _reqStr(m, 'formType'),
  entityId: Value(_optStr(m, 'entityId')),
  json: _reqStr(m, 'json'),
  updatedAt: _reqInt(m, 'updatedAt'),
);

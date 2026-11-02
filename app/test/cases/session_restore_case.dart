import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ephemeron/app/session/session_restore.dart';
import 'package:ephemeron/features/settings/data/settings_repository.dart';

void main() {
  test('draft expiry windows: silent, confirm, expired', () {
    const now = 1000000000000;
    const hour = 60 * 60 * 1000;
    expect(draftIsExpired(now - hour, now), isFalse);
    expect(draftNeedsConfirm(now - hour, now), isFalse);
    expect(draftNeedsConfirm(now - 25 * hour, now), isTrue);
    expect(draftIsExpired(now - 25 * hour, now), isFalse);
    expect(draftIsExpired(now - 8 * 24 * hour, now), isTrue);
    expect(draftNeedsConfirm(now - 8 * 24 * hour, now), isFalse);
  });

  test('draft id is deterministic per form and entity', () {
    expect(draftIdFor('task', null), 'task');
    expect(draftIdFor('task', 'new'), 'task:new');
    expect(draftIdFor('task', 'abc'), 'task:abc');
  });

  test('session keys round trip', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repo = SettingsRepository(await SharedPreferences.getInstance());
    expect(repo.lastTabIndex, 0);
    expect(repo.openSheet, isNull);
    await repo.setLastTabIndex(4);
    await repo.setLastRoute('/tab4');
    await repo.setOpenSheet('task_new');
    expect(repo.lastTabIndex, 4);
    expect(repo.lastRoute, '/tab4');
    expect(repo.openSheet, 'task_new');
    expect(repo.openSheetAtMs, isNotNull);
    await repo.setCalendarDayCount(3);
    await repo.setCalendarAnchorMs(123);
    expect(repo.calendarDayCount, 3);
    expect(repo.calendarAnchorMs, 123);
    await repo.setSelectedTaskListId('list-1');
    await repo.setSelectedNotesFolderId('folder-1');
    expect(repo.selectedTaskListId, 'list-1');
    expect(repo.selectedNotesFolderId, 'folder-1');
    await repo.setSearchQuery('milk');
    await repo.setSearchScope('tasks');
    expect(repo.searchQuery, 'milk');
    expect(repo.searchScope, 'tasks');
    await repo.setFocusSetup(
      focusMin: 50,
      breakMin: 10,
      isBreak: true,
      taskId: () => 't1',
      habitId: () => 'h1',
    );
    expect(repo.focusSetupMin, 50);
    expect(repo.focusBreakMin, 10);
    expect(repo.focusIsBreak, isTrue);
    expect(repo.focusTaskId, 't1');
    expect(repo.focusHabitId, 'h1');
    await repo.setOpenSheet(null);
    expect(repo.openSheet, isNull);
    expect(repo.openSheetAtMs, isNull);
  });
}

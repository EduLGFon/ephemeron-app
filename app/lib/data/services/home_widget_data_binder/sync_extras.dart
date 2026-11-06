part of '../home_widget_data_binder.dart';

extension HomeWidgetDataBinderSyncExtras on HomeWidgetDataBinder {
  Future<void> _refreshSyncStatus() async {
    try {
      await _svc.updateByPrefix(
        keyPrefix: 'sync_status',
        title: 'Sync',
        body: 'Updated ${DateTime.now().toLocal()}',
      );
      _mark('sync_status');
    } catch (_) {}
  }

  Future<void> _refreshExtras() async {
    try {
      final alarmRepo = ref.read(alarmRepositoryProvider);
      final upcoming = await alarmRepo.watchUpcoming().first;
      await _svc.updateByPrefix(
        keyPrefix: 'alarm_status',
        title: 'Alarms',
        body: '${upcoming.length} upcoming',
      );
      _mark('alarm_status');
    } catch (_) {}
    try {
      final taskRepo = ref.read(taskRepositoryProvider);
      final tags = await taskRepo.watchTags().first;
      await _svc.updateByPrefix(
        keyPrefix: 'tag_shortcuts',
        title: 'Tags',
        body: tags.isEmpty ? 'No tags.' : tags.map((t) => t.name).join(', '),
      );
      _mark('tag_shortcuts');
      final folders = await ref
          .read(noteRepositoryProvider)
          .watchChildFolders(null)
          .first;
      await _svc.updateByPrefix(
        keyPrefix: 'folder_shortcuts',
        title: 'Folders',
        body: folders.isEmpty
            ? 'No folders.'
            : folders.map((f) => f.name).join(', '),
      );
      _mark('folder_shortcuts');
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString('last_backup_at');
      await _svc.updateByPrefix(
        keyPrefix: 'backup_status',
        title: 'Backup',
        body: last == null ? 'No backup yet.' : 'Last: $last',
      );
      _mark('backup_status');
    } catch (_) {}
    try {
      final occRepo = ref.read(occurrenceRepositoryProvider);
      final now = DateTime.now();
      final key =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final occs = await occRepo.watchDay(key).first;
      final current = occs.where((o) {
        final start = o.startUtc;
        return start <= now.millisecondsSinceEpoch &&
            o.endUtc >= now.millisecondsSinceEpoch;
      }).toList();
      await _svc.updateByPrefix(
        keyPrefix: 'free_busy',
        title: current.isEmpty ? 'Free' : 'Busy',
        body: current.isEmpty ? 'No current event.' : current.first.title,
      );
      _mark('free_busy');
      if (occs.isNotEmpty) {
        final nextMeeting = occs.firstWhere(
          (o) => o.startUtc > now.millisecondsSinceEpoch,
          orElse: () => occs.first,
        );
        await _svc.updateByPrefix(
          keyPrefix: 'next_meeting',
          title: nextMeeting.title,
          body: 'Next meeting',
        );
        _mark('next_meeting');
      }
    } catch (_) {}
  }
}

part of '../backend_sync_engine.dart';

mixin _BackendSyncPullOps on _BackendSyncEngineBase {
  @override
  Future<void> _pull(BackendSyncApi api) async {
    final since = await _cursor(_BackendSyncEngineBase._pullCursorKey);
    final pulled = await api.pull(since);
    var maxTs = since;
    int tsOf(Map<String, dynamic> m) => (m['updatedAt'] as int?) ?? 0;

    for (final m in pulled.habits) {
      final ts = tsOf(m);
      if (ts > maxTs) maxTs = ts;
      await _mergeHabit(m);
    }
    var maxLogTs = await _cursor(_BackendSyncEngineBase._logsCursorKey);
    var maxFocusTs = await _cursor(_BackendSyncEngineBase._focusCursorKey);
    for (final m in pulled.habitLogs) {
      final ts = tsOf(m);
      if (ts > maxTs) maxTs = ts;
      if (ts > maxLogTs) maxLogTs = ts;
      await _mergeLog(m);
    }
    for (final m in pulled.focusSessions) {
      final ts = tsOf(m);
      if (ts > maxTs) maxTs = ts;
      if (ts > maxFocusTs) maxFocusTs = ts;
      await _mergeFocus(m);
    }
    // Pulled rows are in sync; do not echo them back on the next push.
    await _setCursor(_BackendSyncEngineBase._logsCursorKey, maxLogTs);
    await _setCursor(_BackendSyncEngineBase._focusCursorKey, maxFocusTs);
    if (maxTs > since)
      await _setCursor(_BackendSyncEngineBase._pullCursorKey, maxTs);
  }
}

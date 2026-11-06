part of '../headless_widget_push.dart';

/// Rebuilds the occurrence window headless (pure Dart + drift, no channels)
/// so background agenda widgets read fresh data instead of a stale cache.
Future<void> rebuildOccurrenceWindowHeadless(AppDatabase db) async {
  try {
    final now = DateTime.now().toUtc();
    await OccurrenceRepository(db).rebuildWindow(
      windowStartUtc: now.subtract(const Duration(days: 1)),
      windowEndUtc: now.add(const Duration(days: 8)),
    );
  } catch (_) {}
}

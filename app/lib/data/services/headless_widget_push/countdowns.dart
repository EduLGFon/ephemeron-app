part of '../headless_widget_push.dart';

Future<void> pushCountdownWidgets(AppDatabase db, {String? pinnedId}) async {
  try {
    final all = await CountdownRepository(db).watchCountdowns().first;
    final items = pinnedId == null
        ? all
        : ([
            ...all.where((c) => c.id == pinnedId),
            ...all.where((c) => c.id != pinnedId),
          ]);
    if (items.isEmpty) return;
    final next = items.first;
    final target = DateTime.tryParse(next.targetDate ?? '') ?? DateTime.now();
    final days = target.difference(DateTime.now()).inDays;
    await _push(
      'countdown',
      'CountdownWidgetProvider',
      next.title,
      '$days days remaining',
    );
  } catch (_) {}
}

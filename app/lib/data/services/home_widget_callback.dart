import 'package:home_widget/home_widget.dart';

@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) async {
  // Best-effort: mark widgets as refreshed when a widget is tapped.
  try {
    await HomeWidget.saveWidgetData<String>('sync_status_title', 'Updated');
    await HomeWidget.updateWidget(
      androidName: 'SyncStatusWidgetProvider',
      qualifiedAndroidName: 'com.spotnik.ephemeron.SyncStatusWidgetProvider',
    );
  } catch (_) {}
}
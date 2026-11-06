part of '../headless_widget_push.dart';

Future<void> _push(
  String prefix,
  String provider,
  String title,
  String body, {
  Map<String, String>? extra,
}) async {
  try {
    await HomeWidget.saveWidgetData<String>('${prefix}_title', title);
    await HomeWidget.saveWidgetData<String>('${prefix}_body', body);
    if (extra != null) {
      for (final entry in extra.entries) {
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_${entry.key}',
          entry.value,
        );
      }
    }
    await HomeWidget.updateWidget(
      androidName: provider,
      qualifiedAndroidName: 'com.spotnik.ephemeron.$provider',
    );
  } catch (_) {}
}

/// Reads a widget binding (list/note/countdown/tag/habit id) stored by the
/// settings screen. Null when unconfigured.
Future<String?> readWidgetBinding(String provider) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('widget_config_$provider');
    return (v == null || v.isEmpty) ? null : v;
  } catch (_) {
    return null;
  }
}

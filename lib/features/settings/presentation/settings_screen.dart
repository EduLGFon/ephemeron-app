import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/utils/dev_logger.dart';
import '../../calendar/application/calendar_providers.dart';
import '../../../core/settings/app_settings_provider.dart';

import 'settings_google_account_section.dart';
import 'settings_appearance_section.dart';
import 'settings_calendar_section.dart';
import 'settings_sync_section.dart';
import 'settings_notifications_section.dart';
import 'settings_about_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          SettingsGoogleAccountSection(),
          Divider(),
          SettingsAppearanceSection(),
          Divider(),
          SettingsCalendarSection(),
          Divider(),
          SettingsSyncSection(),
          Divider(),
          SettingsNotificationsSection(),
          Divider(),
          SettingsAboutSection(),
        ],
      ),
    );
  }

  static Color parseColor(String hex) {
    try {
      var c = hex.replaceAll('#', '').trim();
      if (c.length == 6) c = 'FF$c';
      return Color(int.parse(c, radix: 16));
    } catch (_) {
      return const Color(0xFF005F73);
    }
  }

  static void editThemeColor(
      BuildContext context, WidgetRef ref, String type, Color current) {
    final hexString =
        '#${current.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
    final controller = TextEditingController(text: hexString);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text('Custom $type Color',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(hintText: '#FF6C63FF'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) {
                try {
                  final color = parseColor(val);
                  if (type == 'Primary') {
                    ref
                        .read(themeEngineProvider.notifier)
                        .setPrimaryColor(color);
                  } else {
                    ref
                        .read(themeEngineProvider.notifier)
                        .setBackgroundColor(color);
                  }
                } catch (_) {}
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  static void showDevLogsDialog(BuildContext context, WidgetRef ref) {
    final palette = ref.read(themeEngineProvider);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: palette.surface,
          surfaceTintColor: Colors.transparent,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Developer Logs', style: TextStyle(color: palette.text)),
              TextButton(
                onPressed: () {
                  DevLogger.clear();
                  Navigator.of(context).pop();
                },
                child: const Text('Clear'),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: DevLogger.logs.isEmpty
                ? Center(
                    child: Text(
                      'No logs yet.',
                      style:
                          TextStyle(color: palette.text.withValues(alpha: 0.5)),
                    ),
                  )
                : ListView.builder(
                    itemCount: DevLogger.logs.length,
                    itemBuilder: (context, index) {
                      final log =
                          DevLogger.logs[DevLogger.logs.length - 1 - index];
                      final isError = log.error != null;
                      final timeStr =
                          "${log.time.hour.toString().padLeft(2, '0')}:${log.time.minute.toString().padLeft(2, '0')}:${log.time.second.toString().padLeft(2, '0')}";
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isError
                              ? Colors.redAccent.withValues(alpha: 0.1)
                              : palette.text.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '[$timeStr] ${log.message}',
                              style: TextStyle(
                                color:
                                    isError ? Colors.redAccent : palette.text,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                            if (log.error != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Error: ${log.error}',
                                style: TextStyle(
                                  color: Colors.redAccent.shade200,
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                            if (log.stackTrace != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                log.stackTrace!,
                                style: TextStyle(
                                  color: palette.text.withValues(alpha: 0.4),
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                ),
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                final text = DevLogger.logs.map((log) {
                  final timeStr =
                      "${log.time.hour.toString().padLeft(2, '0')}:${log.time.minute.toString().padLeft(2, '0')}:${log.time.second.toString().padLeft(2, '0')}";
                  var msg = '[$timeStr] ${log.message}';
                  if (log.error != null) msg += '\nError: ${log.error}';
                  if (log.stackTrace != null) {
                    msg += '\nStackTrace: ${log.stackTrace}';
                  }
                  return msg;
                }).join('\n\n');
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logs copied to clipboard')),
                );
              },
              child: const Text('Copy Logs'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  static void editSoundPath(
      BuildContext context, WidgetRef ref, String type, String current) {
    final controller = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
            'Edit ${type == 'short' ? 'Short' : 'Long'} Alarm Sound Path',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(hintText: '/path/to/sound.wav'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final path = controller.text.trim();
              if (path.isNotEmpty) {
                if (type == 'short') {
                  ref
                      .read(appSettingsProvider.notifier)
                      .setAlarmShortSoundPath(path);
                } else {
                  ref
                      .read(appSettingsProvider.notifier)
                      .setAlarmLongSoundPath(path);
                }
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  static void editAlarmBackground(
      BuildContext context, WidgetRef ref, String current) {
    final controller = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: const Text('Edit Alarm Background Hex Color',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(hintText: '#005F73'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) {
                ref.read(appSettingsProvider.notifier).setAlarmBackground(val);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  static String dayName(int isoDay) {
    const names = {
      1: 'Monday',
      2: 'Tuesday',
      3: 'Wednesday',
      4: 'Thursday',
      5: 'Friday',
      6: 'Saturday',
      7: 'Sunday',
    };
    return names[isoDay] ?? 'Sunday';
  }

  static void showStartDayPicker(
      BuildContext context, WidgetRef ref, int current) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('First day of the week',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              for (final day in [7, 1, 6])
                RadioListTile<int>(
                  title: Text(dayName(day)),
                  value: day,
                  // ignore: deprecated_member_use
                  groupValue: current,
                  // ignore: deprecated_member_use
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setCalendarStartDay(value);
                      Navigator.pop(sheetContext);
                    }
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  static void showDeviceCalendarsSheet(BuildContext context, WidgetRef ref) {
    final palette = ref.read(themeEngineProvider);
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Consumer(
            builder: (context, ref, _) {
              final calendarsAsync = ref.watch(deviceCalendarsProvider);
              final settings = ref.watch(appSettingsProvider);

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Device Calendars',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: palette.text,
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'Select which calendars from your phone you want to see inside Ephemeron.',
                      style: TextStyle(
                        color: palette.text.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Divider(),
                  Flexible(
                    child: calendarsAsync.when(
                      data: (calendars) {
                        if (calendars.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No calendars found. Please check calendar permissions in your phone settings.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: palette.text.withValues(alpha: 0.6)),
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: calendars.length,
                          itemBuilder: (context, index) {
                            final cal = calendars[index];
                            final isEnabled = settings.enabledDeviceCalendarIds
                                .contains(cal.id);
                            final calColor = cal.color ?? palette.primary;

                            return SwitchListTile(
                              title: Row(
                                children: [
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: calColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(cal.name,
                                        style: TextStyle(color: palette.text)),
                                  ),
                                ],
                              ),
                              subtitle: cal.accountName != null
                                  ? Text(
                                      cal.accountName!,
                                      style: TextStyle(
                                        color:
                                            palette.text.withValues(alpha: 0.5),
                                        fontSize: 11,
                                      ),
                                    )
                                  : null,
                              value: isEnabled,
                              onChanged: (val) {
                                final currentSet = Set<String>.from(
                                    settings.enabledDeviceCalendarIds);
                                if (val) {
                                  currentSet.add(cal.id);
                                } else {
                                  currentSet.remove(cal.id);
                                }
                                ref
                                    .read(appSettingsProvider.notifier)
                                    .setEnabledDeviceCalendarIds(currentSet);
                              },
                            );
                          },
                        );
                      },
                      loading: () => const Center(
                        child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator()),
                      ),
                      error: (err, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Error loading calendars: $err',
                              style: const TextStyle(color: Colors.redAccent)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

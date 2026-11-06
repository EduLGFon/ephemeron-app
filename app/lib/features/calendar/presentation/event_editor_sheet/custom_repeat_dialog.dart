// "Custom repeat" RRULE builder dialog, extracted from the repeat
// dropdown handler. Returns the composed RRULE, or null on cancel.
// An empty result is intended to clear the rule (caller maps it to null).
part of '../event_editor_sheet.dart';

Future<String?> _showCustomRepeatDialog(
  BuildContext context,
  WidgetRef ref,
  String? rrule,
) async {
  // Parse existing rrule into builder state.
  String freq = 'WEEKLY';
  int interval = 1;
  final byDay = <String>{};
  int? monthDay;
  String endMode = 'never';
  int count = 10;
  DateTime? until;
  if (rrule != null && rrule.isNotEmpty) {
    try {
      final r = RecurrenceRule.parse(rrule);
      freq = r.freq;
      interval = r.interval;
      byDay.addAll(r.byDay);
      if (r.byMonthDay.isNotEmpty) {
        monthDay = r.byMonthDay.first;
      }
      if (r.count != null) {
        endMode = 'count';
        count = r.count!;
      } else if (r.untilUtc != null || r.untilDate != null) {
        endMode = 'until';
        if (r.untilUtc != null) {
          until = r.untilUtc;
        } else if (r.untilDate != null) {
          final p = r.untilDate!.split('-');
          until = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
        }
      }
    } catch (_) {}
  }
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: const Text('Custom repeat'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: freq,
                decoration: const InputDecoration(labelText: 'Frequency'),
                items: const [
                  DropdownMenuItem(value: 'DAILY', child: Text('Daily')),
                  DropdownMenuItem(value: 'WEEKLY', child: Text('Weekly')),
                  DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly')),
                  DropdownMenuItem(value: 'YEARLY', child: Text('Yearly')),
                ],
                onChanged: (x) => setSt(() => freq = x!),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Every'),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: TextEditingController(
                        text: interval.toString(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (t) => interval = int.tryParse(t) ?? 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    freq == 'DAILY'
                        ? 'day(s)'
                        : freq == 'WEEKLY'
                        ? 'week(s)'
                        : freq == 'MONTHLY'
                        ? 'month(s)'
                        : 'year(s)',
                  ),
                ],
              ),
              if (freq == 'WEEKLY') ...[
                const SizedBox(height: 8),
                const Text('On days'),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final d in const [
                      'MO',
                      'TU',
                      'WE',
                      'TH',
                      'FR',
                      'SA',
                      'SU',
                    ])
                      FilterChip(
                        label: Text(d),
                        selected: byDay.contains(d),
                        onSelected: (sel) => setSt(() {
                          if (sel) {
                            byDay.add(d);
                          } else {
                            byDay.remove(d);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              if (freq == 'MONTHLY') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Day of month:'),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 60,
                      child: TextField(
                        controller: TextEditingController(
                          text: (monthDay ?? 1).toString(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (t) => monthDay = int.tryParse(t),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('(-1 = last day)'),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: endMode,
                decoration: const InputDecoration(labelText: 'Ends'),
                items: const [
                  DropdownMenuItem(value: 'never', child: Text('Never')),
                  DropdownMenuItem(
                    value: 'count',
                    child: Text('After N times'),
                  ),
                  DropdownMenuItem(value: 'until', child: Text('On date')),
                ],
                onChanged: (x) => setSt(() => endMode = x!),
              ),
              if (endMode == 'count') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Times:'),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 60,
                      child: TextField(
                        controller: TextEditingController(
                          text: count.toString(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (t) => count = int.tryParse(t) ?? count,
                      ),
                    ),
                  ],
                ),
              ],
              if (endMode == 'until') ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    SettingsRepository? settings;
                    try {
                      settings = await ref.read(
                        settingsRepositoryProvider.future,
                      );
                    } catch (_) {}
                    final initial =
                        until ??
                        resolvePickerDate(
                          current: null,
                          remembered: settings?.getPickerDate(
                            PickerMemoryKeys.eventRruleUntil,
                          ),
                          fallback: DateTime.now(),
                        );
                    if (!ctx.mounted) return;
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: initial,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      try {
                        await settings?.setPickerDate(
                          PickerMemoryKeys.eventRruleUntil,
                          formatYmd(picked),
                        );
                      } catch (_) {}
                      setSt(() => until = picked);
                    }
                  },
                  child: Text(
                    until == null
                        ? 'Pick date'
                        : DeviceDateFormat.yMMMd(ctx).format(until!),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parts = <String>['FREQ=$freq'];
              if (interval > 1) {
                parts.add('INTERVAL=$interval');
              }
              if (freq == 'WEEKLY' && byDay.isNotEmpty) {
                parts.add('BYDAY=${byDay.join(',')}');
              }
              if (freq == 'MONTHLY' && monthDay != null) {
                parts.add('BYMONTHDAY=$monthDay');
              }
              if (endMode == 'count') {
                parts.add('COUNT=$count');
              } else if (endMode == 'until' && until != null) {
                parts.add(
                  'UNTIL=${until!.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first}Z',
                );
              }
              Navigator.of(ctx).pop(parts.join(';'));
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}

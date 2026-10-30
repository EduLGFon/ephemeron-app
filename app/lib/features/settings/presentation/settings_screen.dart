import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ephemeron/l10n/src/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../auth/presentation/auth_screen.dart';
import '../application/settings_providers.dart';
import '../data/backup_service.dart';
import '../data/settings_repository.dart';
import '../../../core/theme/theme_tokens.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _mutate(
    WidgetRef ref,
    Future<void> Function(SettingsRepository repo) fn,
  ) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    await fn(repo);
    ref.invalidate(settingsRepositoryProvider);
  }

  Future<void> _setHex(
    BuildContext context,
    WidgetRef ref,
    bool primary,
    String raw,
  ) async {
    final v = raw.trim();
    if (v.isEmpty) return;
    if (!isValidHex(v)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid hex like #RRGGBB.')),
      );
      return;
    }
    await _mutate(
      ref,
      (r) => primary ? r.setPrimaryColorHex(v) : r.setBackgroundColorHex(v),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRepo = ref.watch(settingsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: asyncRepo.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (repo) => ListView(
          children: [
            const _SectionHeader('Appearance'),
            ListTile(
              title: Text(AppLocalizations.of(context).languageTitle),
              trailing: DropdownButton<String>(
                value: repo.localeCode,
                items: [
                  DropdownMenuItem(
                    value: 'system',
                    child: Text(AppLocalizations.of(context).languageSystem),
                  ),
                  DropdownMenuItem(
                    value: 'en',
                    child: Text(AppLocalizations.of(context).languageEnglish),
                  ),
                  DropdownMenuItem(
                    value: 'pt',
                    child: Text(
                      AppLocalizations.of(context).languagePortuguese,
                    ),
                  ),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  await repo.setLocaleCode(v);
                  ref.invalidate(settingsRepositoryProvider);
                },
              ),
            ),
            ListTile(
              title: const Text('Primary color'),
              subtitle: Wrap(
                spacing: 8,
                children: [
                  for (final c in primaryPresets)
                    GestureDetector(
                      onTap: () =>
                          _mutate(ref, (r) => r.setPrimaryColorHex(_hex(c))),
                      child: CircleAvatar(backgroundColor: c, radius: 14),
                    ),
                ],
              ),
            ),
            ListTile(
              title: const Text('Background color'),
              subtitle: Wrap(
                spacing: 8,
                children: [
                  for (final c in backgroundPresets)
                    GestureDetector(
                      onTap: () =>
                          _mutate(ref, (r) => r.setBackgroundColorHex(_hex(c))),
                      child: CircleAvatar(backgroundColor: c, radius: 14),
                    ),
                ],
              ),
            ),
            ListTile(
              title: const Text('Brightness'),
              trailing: DropdownButton<String>(
                value: repo.brightness,
                items: const [
                  DropdownMenuItem(value: 'light', child: Text('Light')),
                  DropdownMenuItem(value: 'dark', child: Text('Dark')),
                  DropdownMenuItem(value: 'amoled', child: Text('AMOLED')),
                ],
                onChanged: (v) {
                  if (v != null) _mutate(ref, (r) => r.setBrightness(v));
                },
              ),
            ),
            ListTile(
              title: const Text('Custom primary hex'),
              trailing: SizedBox(
                width: 120,
                child: TextField(
                  decoration: const InputDecoration(hintText: '#RRGGBB'),
                  onSubmitted: (v) => _setHex(context, ref, true, v),
                ),
              ),
            ),
            ListTile(
              title: const Text('Custom background hex'),
              trailing: SizedBox(
                width: 120,
                child: TextField(
                  decoration: const InputDecoration(hintText: '#RRGGBB'),
                  onSubmitted: (v) => _setHex(context, ref, false, v),
                ),
              ),
            ),
            const _SectionHeader('Power and accessibility'),
            ListTile(
              title: const Text('Power saving mode'),
              trailing: DropdownButton<String>(
                value: repo.powerSavingMode.name,
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('Auto')),
                  DropdownMenuItem(value: 'on', child: Text('On')),
                  DropdownMenuItem(value: 'off', child: Text('Off')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    _mutate(
                      ref,
                      (r) => r.setPowerSavingMode(
                        PowerSavingMode.values.firstWhere((e) => e.name == v),
                      ),
                    );
                  }
                },
              ),
            ),
            SwitchListTile(
              title: const Text('Reduce animations'),
              value: repo.reduceAnimations,
              onChanged: (v) => _mutate(ref, (r) => r.setReduceAnimations(v)),
            ),
            SwitchListTile(
              title: const Text('Haptics'),
              value: repo.haptics,
              onChanged: (v) => _mutate(ref, (r) => r.setHaptics(v)),
            ),
            const _SectionHeader('Navigation'),
            ListTile(
              title: const Text('Reorder sections'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _reorder(context, ref, repo),
            ),
            ListTile(
              title: const Text('Account and sync'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
              ),
            ),
            _SectionHeader(AppLocalizations.of(context).backupTitle),
            const _BackupSection(),
          ],
        ),
      ),
    );
  }

  String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    SettingsRepository repo,
  ) async {
    final current = List<int>.from(repo.navOrder);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              children: [
                Expanded(
                  child: ReorderableListView(
                    onReorderItem: (oldIndex, newIndex) {
                      setSt(() {
                        final item = current.removeAt(oldIndex);
                        current.insert(newIndex, item);
                      });
                    },
                    children: [
                      for (final idx in current)
                        ListTile(
                          key: ValueKey(idx),
                          title: Text(AppSectionLabel.label(idx)),
                          trailing: const Icon(Icons.drag_handle),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () async {
                      await repo.setNavOrder(current);
                      ref.invalidate(settingsRepositoryProvider);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

// Avoid importing app_sections enum naming mismatch.
class AppSectionLabel {
  static String label(int idx) {
    const names = [
      'Calendar',
      'Tasks',
      'Matrix',
      'Habits',
      'Countdowns',
      'Focus',
      'Notes',
    ];
    return names[idx];
  }
}

class _BackupSection extends ConsumerStatefulWidget {
  const _BackupSection();

  @override
  ConsumerState<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<_BackupSection> {
  List<FileSystemEntity> _files = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshFiles();
  }

  Future<Directory> _backupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/backups');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _refreshFiles() async {
    try {
      final dir = await _backupDir();
      final files = await dir
          .list()
          .where((e) => e.path.endsWith('.json'))
          .toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      if (mounted) setState(() => _files = files);
    } catch (_) {
      // Storage unavailable: section stays empty.
    }
  }

  @override
  Widget build(BuildContext context) {
    // path_provider has no documents directory on web; export/import
    // files are a native-only feature for now.
    if (kIsWeb) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text('File backups are not available on web yet.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton(
            onPressed: _busy ? null : _export,
            child: Text(AppLocalizations.of(context).backupExport),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(AppLocalizations.of(context).backupNote),
        ),
        for (final f in _files)
          ListTile(
            title: Text(f.path.split('/').last),
            trailing: TextButton(
              onPressed: _busy
                  ? null
                  : () => _confirmRestore(context, File(f.path)),
              child: Text(AppLocalizations.of(context).backupRestore),
            ),
          ),
      ],
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final service = ref.read(backupServiceProvider);
      final raw = service.encode(await service.exportJson());
      final dir = await _backupDir();
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final file = File('${dir.path}/ephemeron-backup-$stamp.json');
      await file.writeAsString(raw);
      await _refreshFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              ).backupExported(file.path.split('/').last),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).backupExportFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRestore(BuildContext context, File file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).backupRestoreTitle),
        content: Text(AppLocalizations.of(context).backupRestoreBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context).backupCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.of(context).backupRestore),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(backupServiceProvider);
      await service.restoreJson(service.decode(await file.readAsString()));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).backupRestored)),
        );
      }
    } on BackupFormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

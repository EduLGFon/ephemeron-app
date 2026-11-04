// Backup export and restore controls for the settings screen.
import 'dart:io';

import 'package:ephemeron/l10n/src/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../application/settings_providers.dart';
import '../data/backup_service.dart';

class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
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

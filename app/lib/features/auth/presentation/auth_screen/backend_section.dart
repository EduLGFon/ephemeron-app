part of '../auth_screen.dart';

class _BackendSection extends ConsumerStatefulWidget {
  const _BackendSection();
  @override
  ConsumerState<_BackendSection> createState() => _BackendSectionState();
}

class _BackendSectionState extends ConsumerState<_BackendSection> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  String? _emailError;
  String? _passwordError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(backendAccountProvider.notifier).restore());
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backendEmail = ref.watch(backendAccountProvider);
    final syncStatus = ref.watch(backendSyncStatusProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Habits and focus sync',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Optional account that syncs only habits and focus sessions between your devices. Calendar, tasks and notes stay on this device.',
        ),
        const SizedBox(height: 12),
        if (backendEmail == null) ...[
          TextField(
            controller: _email,
            decoration: InputDecoration(
              labelText: 'Email',
              errorText: _emailError,
            ),
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) {
              if (_emailError != null) setState(() => _emailError = null);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _password,
            decoration: InputDecoration(
              labelText: 'Password (8+ characters)',
              errorText: _passwordError,
            ),
            obscureText: true,
            onChanged: (_) {
              if (_passwordError != null) setState(() => _passwordError = null);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _submit(login: true),
                  child: const Text('Sign in'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _submit(login: false),
                  child: const Text('Create account'),
                ),
              ),
            ],
          ),
        ] else ...[
          ListTile(
            title: Text(backendEmail),
            subtitle: Text('Backend sync: ${syncStatus.name}'),
            contentPadding: EdgeInsets.zero,
          ),
          FilledButton(
            onPressed: syncStatus == SyncStatus.syncing
                ? null
                : () => ref.read(backendSyncStatusProvider.notifier).syncNow(),
            child: const Text('Sync now'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      ref.read(backendAccountProvider.notifier).signOut(),
                  child: const Text('Sign out'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _confirmDelete(context),
                  child: const Text('Delete remote data'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _submit({required bool login}) async {
    final email = _email.text.trim();
    final password = _password.text;
    String? emailErr;
    String? passErr;
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      emailErr = 'Enter a valid email';
    }
    if (password.length < 8) {
      passErr = 'Password must be at least 8 characters';
    }
    if (emailErr != null || passErr != null) {
      setState(() {
        _emailError = emailErr;
        _passwordError = passErr;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _emailError = null;
      _passwordError = null;
    });
    try {
      final notifier = ref.read(backendAccountProvider.notifier);
      if (login) {
        await notifier.login(_email.text.trim(), _password.text);
      } else {
        await notifier.signUp(_email.text.trim(), _password.text);
      }
      await ref.read(backendSyncStatusProvider.notifier).syncNow();
      await ref.read(backendAutoSyncServiceProvider).reschedule();
    } on BackendApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete remote data?'),
        content: const Text(
          'This permanently deletes your habits and focus sessions from the server. '
          'Your on-device data stays. A JSON backup is saved to your documents folder first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    String? backupPath;
    try {
      backupPath = await _exportBackup(ref);
    } catch (e) {
      debugPrint('pre-delete backup failed: $e');
    }
    try {
      await ref.read(backendAuthProvider).deleteAccount();
      await ref.read(backendAccountProvider.notifier).signOut();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              backupPath == null
                  ? 'Remote data deleted.'
                  : 'Remote data deleted. Backup saved to $backupPath',
            ),
          ),
        );
      }
    } on BackendApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Saves a full JSON backup before remote-data deletion (export-first).
  Future<String> _exportBackup(WidgetRef ref) async {
    final db = ref.read(appDatabaseProvider);
    final service = BackupService(db);
    final backup = await service.exportJson();
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/ephemeron-backup-$stamp.json');
    await file.writeAsString(service.encode(backup), flush: true);
    return file.path;
  }
}

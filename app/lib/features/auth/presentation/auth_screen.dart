// Sign-in screen: Google (consent-first, works-without-account) plus
// backend email account for habits/focus sync. Google data never
// touches the backend; the backend only stores habits and focus sessions.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart'
    if (dart.library.io) 'google_signin_web_stub.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/db/db_provider.dart';
import '../../../data/remote/backend_api_client.dart';
import '../../settings/data/backup_service.dart';
import '../../sync/application/sync_providers.dart';
import '../../sync/data/sync_engine.dart';
import '../application/auth_providers.dart';
import '../data/google_auth.dart';
import '../data/microsoft_auth.dart';

class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key});

  Future<void> _googleSignIn(BuildContext context, WidgetRef ref) async {
    debugPrint('AuthScreen._googleSignIn');
    try {
      await ref.read(googleAccountProvider.notifier).signIn(tasks: true);
      debugPrint('AuthScreen signIn returned');
      // Sync starts right after sign-in, then auto-sync takes over.
      await ref.read(syncStatusProvider.notifier).syncNow();
      await ref.read(googleAutoSyncServiceProvider).start();
    } on GoogleAuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      // Never mask the real failure behind the offline message: the app
      // works offline, but a failed sign-in deserves its actual cause
      // (for example a missing serverClientId or SHA-1 mismatch).
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Google sign-in failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(googleAccountsProvider);
    final email = ref.watch(googleAccountProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Google data (Calendar and Tasks) goes directly from this device to Google. It never touches our server.',
          ),
          const SizedBox(height: 16),
          if (accounts.isEmpty) ...[
            if (kIsWeb)
              _WebGoogleButton(ref: ref)
            else
              FilledButton(
                onPressed: () => _googleSignIn(context, ref),
                child: const Text('Sign in with Google'),
              ),
            const SizedBox(height: 8),
            const Text('The app works fully offline without any account.'),
          ] else ...[
            const _ReconnectBanner(),
            for (final a in accounts)
              ListTile(
                title: Text(a),
                subtitle: Text(a == email ? 'Active' : 'Connected to Google'),
                trailing: IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () =>
                      ref.read(googleAccountProvider.notifier).signOut(a),
                ),
                onTap: () =>
                    ref.read(googleAccountProvider.notifier).setActive(a),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _googleSignIn(context, ref),
              child: const Text('Add account'),
            ),
          ],
          const Divider(height: 32),
          const _MicrosoftSection(),
          const Divider(height: 32),
          const _BackendSection(),
        ],
      ),
    );
  }
}

/// Banner shown when a signed-in account needs its Google grant renewed
/// (expired token, revoked access, or a grant from before Tasks sync that
/// only covers Calendar). Queued rows are kept, so reconnecting resumes
/// sync without data loss.
class _ReconnectBanner extends ConsumerWidget {
  const _ReconnectBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(googleReconsentAccountsProvider);
    if (accounts.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Google sync needs permission again for: ${accounts.join(', ')}. '
              'Your changes are kept on this device and will sync after reconnecting.',
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _reconnect(context, ref, accounts.first),
              child: const Text('Grant Calendar + Tasks access'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reconnect(
    BuildContext context,
    WidgetRef ref,
    String email,
  ) async {
    try {
      await ref.read(googleAccountProvider.notifier).setActive(email);
      await ref.read(googleAccountProvider.notifier).signIn(tasks: true);
      ref.read(googleReconsentAccountsProvider.notifier).clear(email);
      await ref.read(syncStatusProvider.notifier).syncNow();
      await ref.read(googleAutoSyncServiceProvider).start();
    } on GoogleAuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Google sign-in failed: $e')));
    }
  }
}

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

class _WebGoogleButton extends ConsumerStatefulWidget {
  const _WebGoogleButton({required this.ref});

  final WidgetRef ref;

  @override
  ConsumerState<_WebGoogleButton> createState() => _WebGoogleButtonState();
}

class _WebGoogleButtonState extends ConsumerState<_WebGoogleButton> {
  StreamSubscription<dynamic>? _sub;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    await GoogleSignIn.instance.initialize(
      clientId: AppConfig.webGoogleClientId.isEmpty
          ? null
          : AppConfig.webGoogleClientId,
    );
    _sub = GoogleSignIn.instance.authenticationEvents.listen((event) {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        final account = event.user;
        unawaited(_handle(account));
      }
    });
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _handle(GoogleSignInAccount account) async {
    debugPrint('WebGoogleButton handle account (redacted)');
    try {
      await ref.read(googleAuthProvider).handleWebAccount(account);
      ref.read(googleAccountProvider.notifier).setSignedInEmail(account.email);
      await ref.read(syncStatusProvider.notifier).syncNow();
      await ref.read(googleAutoSyncServiceProvider).start();
      debugPrint('WebGoogleButton done');
    } catch (e, st) {
      debugPrint('WebGoogleButton error: $e\n$st');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox(height: 44);
    return SizedBox(height: 44, child: renderButton());
  }
}

class _MicrosoftSection extends ConsumerStatefulWidget {
  const _MicrosoftSection();
  @override
  ConsumerState<_MicrosoftSection> createState() => _MicrosoftSectionState();
}

class _MicrosoftSectionState extends ConsumerState<_MicrosoftSection> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(microsoftAccountProvider.notifier).restore(),
    );
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(microsoftAccountProvider.notifier).signIn();
    } on MicrosoftAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Microsoft sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientId = AppConfig.microsoftClientId;
    final accounts = ref.watch(microsoftAccountsProvider);
    final active = ref.watch(microsoftAccountProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Microsoft (preview) - experimental sync',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Microsoft account foundation. Calendar and task sync wiring comes next.',
        ),
        const SizedBox(height: 12),
        if (clientId.isEmpty) ...[
          const Text('Microsoft sign-in is not configured for this build.'),
        ] else if (accounts.isEmpty) ...[
          FilledButton(
            onPressed: _busy ? null : _signIn,
            child: const Text('Sign in with Microsoft'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ] else ...[
          for (final a in accounts)
            ListTile(
              title: Text(a),
              subtitle: Text(a == active ? 'Active' : 'Connected to Microsoft'),
              trailing: IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () =>
                    ref.read(microsoftAccountProvider.notifier).signOut(a),
              ),
              onTap: () =>
                  ref.read(microsoftAccountProvider.notifier).setActive(a),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _signIn,
            child: const Text('Add account'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ],
    );
  }
}

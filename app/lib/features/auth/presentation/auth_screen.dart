// Sign-in screen: Google (consent-first, works-without-account) plus
// backend email account for habits/focus sync. Google data never
// touches the backend; the backend only stores habits and focus sessions.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../data/remote/backend_api_client.dart';
import '../../sync/application/sync_providers.dart';
import '../../sync/data/sync_engine.dart';
import '../application/auth_providers.dart';
import '../data/google_auth.dart';
import '../../../core/config/app_config.dart';

import 'package:google_sign_in_web/web_only.dart'
    if (dart.library.io) 'google_signin_web_stub.dart';

class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key});

  Future<void> _googleSignIn(BuildContext context, WidgetRef ref) async {
    debugPrint('AuthScreen._googleSignIn');
    try {
      await ref.read(googleAccountProvider.notifier).signIn();
      debugPrint('AuthScreen signIn returned');
      // Sync starts right after sign-in, then auto-sync takes over.
      await ref.read(syncStatusProvider.notifier).syncNow();
      await ref.read(googleAutoSyncServiceProvider).start();
    } on GoogleAuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Google sign-in is not available on this platform. '
            'The app works fully offline without an account.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          if (email == null) ...[
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
            ListTile(
              title: Text(email),
              subtitle: const Text('Connected to Google'),
            ),
            OutlinedButton(
              onPressed: () =>
                  ref.read(googleAccountProvider.notifier).signOut(),
              child: const Text('Sign out'),
            ),
          ],
          const Divider(height: 32),
          const _BackendSection(),
        ],
      ),
    );
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
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _password,
            decoration: const InputDecoration(
              labelText: 'Password (8+ characters)',
            ),
            obscureText: true,
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final notifier = ref.read(backendAccountProvider.notifier);
      if (login) {
        await notifier.login(_email.text.trim(), _password.text);
      } else {
        await notifier.signUp(_email.text.trim(), _password.text);
      }
      await ref.read(backendSyncStatusProvider.notifier).syncNow();
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
          'Your on-device data stays. Export via backup first (backup ships in a later update).',
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
    try {
      await ref.read(backendAuthProvider).deleteAccount();
      await ref.read(backendAccountProvider.notifier).signOut();
    } on BackendApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
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
    debugPrint('WebGoogleButton handle account=${account.email}');
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

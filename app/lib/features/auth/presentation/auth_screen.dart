// Sign-in screen: Google (consent-first, works-without-account) plus
// backend email account for habits/focus sync. Google data never
// touches the backend; the backend only stores habits and focus sessions.
//
// Split across `part` files under `auth_screen/` (U10b); this file is the
// stable public entry point.
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

part 'auth_screen/reconnect_banner.dart';
part 'auth_screen/backend_section.dart';
part 'auth_screen/web_google_button.dart';
part 'auth_screen/microsoft_section.dart';

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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      // Never mask the real failure behind the offline message: the app
      // works offline, but a failed sign-in deserves its actual cause
      // (for example a missing serverClientId or SHA-1 mismatch).
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Google sign-in failed: $e')));
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

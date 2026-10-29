// Sign-in screen: consent-first, works-without-account mode,
// re-connect banner for revoked access.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_providers.dart';

class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key});

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
            FilledButton(
              onPressed: () =>
                  ref.read(googleAccountProvider.notifier).signIn(),
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
        ],
      ),
    );
  }
}

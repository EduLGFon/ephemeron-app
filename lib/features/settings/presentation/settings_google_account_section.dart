import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../auth/google/google_auth_provider.dart';
import '../../auth/google/google_auth_repository.dart';
import '../../sync/application/sync_service.dart';

class SettingsGoogleAccountSection extends ConsumerWidget {
  const SettingsGoogleAccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Google Account',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        const GoogleAccountTile(),
      ],
    );
  }
}

class GoogleAccountTile extends ConsumerWidget {
  const GoogleAccountTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(googleAccountProvider);

    return accountAsync.when(
      data: (account) {
        if (account == null) {
          return ListTile(
            leading: const Icon(Icons.account_circle_outlined, size: 40),
            title: const Text('Not connected'),
            subtitle: const Text('Sign in to sync Calendar & Tasks'),
            trailing: FilledButton(
              onPressed: () => _signIn(context, ref),
              child: const Text('Connect'),
            ),
          );
        }
        return ListTile(
          leading: account.photoUrl != null
              ? CircleAvatar(backgroundImage: NetworkImage(account.photoUrl!))
              : const Icon(Icons.account_circle, size: 40),
          title: Text(account.displayName ?? account.email),
          subtitle: Text(account.email),
          trailing: TextButton(
            onPressed: () => ref.read(googleAuthRepositoryProvider).signOut(),
            child: const Text('Disconnect'),
          ),
        );
      },
      loading: () => const ListTile(
        leading: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Checking connection...'),
      ),
      error: (error, _) => ListTile(
        leading: const Icon(Icons.error_outline, size: 40),
        title: const Text('Could not check Google status'),
        subtitle: Text('$error'),
        trailing: FilledButton(
          onPressed: () => _signIn(context, ref),
          child: const Text('Retry'),
        ),
      ),
    );
  }

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(googleAuthRepositoryProvider).signIn();
      try {
        await ref.read(googleAuthRepositoryProvider).getAccessToken(
          const [
            AppConfig.googleCalendarScope,
            AppConfig.googleTasksScope,
          ],
          promptIfNecessary: true,
        );
      } on Exception {}
      unawaited(ref.read(syncServiceProvider.notifier).sync());
    } on GoogleAuthException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }
}

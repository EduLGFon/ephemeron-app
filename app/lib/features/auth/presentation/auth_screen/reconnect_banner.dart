part of '../auth_screen.dart';

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

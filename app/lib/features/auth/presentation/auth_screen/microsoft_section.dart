part of '../auth_screen.dart';

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

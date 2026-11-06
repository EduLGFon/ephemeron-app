part of '../auth_screen.dart';

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

part of '../google_auth.dart';

mixin _GoogleAuthInit on _GoogleAuthBase {
  @override
  Future<void> _ensureInit() async {
    if (_initialized) return;
    if (kIsWeb && AppConfig.webGoogleClientId.isEmpty) {
      throw GoogleAuthException(
        'Google sign-in is not configured for this web build.',
      );
    }
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows) &&
        AppConfig.linuxGoogleClientId.isEmpty) {
      throw GoogleAuthException(
        'Google sign-in is not configured for this desktop build.',
      );
    }
    if (!kIsWeb &&
        defaultTargetPlatform != TargetPlatform.linux &&
        defaultTargetPlatform != TargetPlatform.windows &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      throw GoogleAuthException(
        'Google sign-in is not available on this platform. '
        'The app works fully offline without an account.',
      );
    }
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows) {
      _initialized = true;
      return;
    }
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await GoogleSignIn.instance.initialize(
          serverClientId: AppConfig.webGoogleClientId.isEmpty
              ? null
              : AppConfig.webGoogleClientId,
        );
      } else {
        await GoogleSignIn.instance.initialize(
          clientId: AppConfig.webGoogleClientId.isEmpty
              ? null
              : AppConfig.webGoogleClientId,
        );
      }
    } on UnimplementedError {
      throw GoogleAuthException(
        'Google sign-in is not available on this platform. '
        'The app works fully offline without an account.',
      );
    }
    _initialized = true;
  }
}

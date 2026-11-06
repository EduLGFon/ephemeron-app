part of '../google_auth.dart';

abstract class _GoogleAuthBase {
  _GoogleAuthBase({SafeSecureStorage? storage})
    : _storage = storage ?? SafeSecureStorage();

  final SafeSecureStorage _storage;
  bool _initialized = false;

  Future<void> _ensureInit();
  Future<String?> accessToken();
  final List<String> _accounts = [];
  String? _activeEmail;
  final Map<String, String?> _accessTokens = {};

  List<String> get accounts => List.unmodifiable(_accounts);
  String? get email => _activeEmail;
  bool get isSignedIn => _activeEmail != null && _accounts.isNotEmpty;

  Future<void> setActiveAccount(String email) async {
    if (_accounts.contains(email)) _activeEmail = email;
  }

  List<String> _scopes(bool tasks) =>
      tasks ? AppConfig.googleScopes : [AppConfig.googleScopes.first];

  String _randomString(int length) {
    final rand = Random.secure();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(
      length,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }
}

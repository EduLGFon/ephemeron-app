// Google sign-in (v7 API): incremental scopes, silent token refresh.
// Google tokens live in memory + keystore; they never touch our backend.
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/safe_storage.dart';

class GoogleAuth {
  GoogleAuth({SafeSecureStorage? storage})
    : _storage = storage ?? SafeSecureStorage();

  final SafeSecureStorage _storage;
  bool _initialized = false;
  String? _email;
  String? _accessToken;

  String? get email => _email;
  bool get isSignedIn => _email != null;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: defaultTargetPlatform == TargetPlatform.android
          ? (AppConfig.androidGoogleClientId.isEmpty
                ? null
                : AppConfig.androidGoogleClientId)
          : (AppConfig.webGoogleClientId.isEmpty
                ? null
                : AppConfig.webGoogleClientId),
    );
    _initialized = true;
  }

  /// Signs in requesting only Calendar; Tasks scope is added when the user
  /// turns on Tasks sync (incremental authorization).
  Future<String?> signIn({bool tasks = false}) async {
    await _ensureInit();
    final account = await GoogleSignIn.instance.authenticate(
      scopeHint: tasks
          ? AppConfig.googleScopes
          : [AppConfig.googleScopes.first],
    );
    _email = account.email;
    final authz = await account.authorizationClient.authorizeScopes(
      _scopes(tasks),
    );
    _accessToken = authz.accessToken;
    await _storage.saveGoogleTokens(
      accessToken: _accessToken!,
      expiryMs: DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 50))
          .millisecondsSinceEpoch,
    );
    return _email;
  }

  Future<void> ensureTasksScope() async {
    await _ensureInit();
    final authz = await GoogleSignIn.instance.authorizationClient
        .authorizeScopes(AppConfig.googleScopes);
    _accessToken = authz.accessToken;
  }

  /// Silent access token, refreshing without UI when possible.
  Future<String?> accessToken() async {
    if (_accessToken != null) {
      final exp = await _storage.googleExpiryMs;
      if (exp == null || DateTime.now().toUtc().millisecondsSinceEpoch < exp) {
        return _accessToken;
      }
    }
    await _ensureInit();
    final authz = await GoogleSignIn.instance.authorizationClient
        .authorizationForScopes(AppConfig.googleScopes);
    if (authz == null) return null;
    _accessToken = authz.accessToken;
    await _storage.saveGoogleTokens(
      accessToken: _accessToken!,
      expiryMs: DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 50))
          .millisecondsSinceEpoch,
    );
    return _accessToken;
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    _email = null;
    _accessToken = null;
    await _storage.clearGoogle();
  }

  List<String> _scopes(bool tasks) =>
      tasks ? AppConfig.googleScopes : [AppConfig.googleScopes.first];
}

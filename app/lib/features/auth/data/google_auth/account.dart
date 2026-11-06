part of '../google_auth.dart';

mixin _GoogleAuthAccount on _GoogleAuthBase {
  Future<String?> restore() async {
    final accs = await _storage.googleAccounts();
    _accounts
      ..clear()
      ..addAll(accs);
    if (_accounts.isEmpty) return null;
    _activeEmail = _accounts.first;
    try {
      await _ensureInit();
      final token = await accessToken();
      if (token == null) {
        // keep accounts; token may refresh later
      }
      debugPrint('GoogleAuth.restore ok');
      return _activeEmail;
    } catch (e) {
      debugPrint('GoogleAuth.restore failed: $e');
      return _activeEmail;
    }
  }

  Future<void> signOut([String? account]) async {
    final target = account ?? _activeEmail;
    if (target == null) return;
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows) {
      _accessTokens.remove(target);
      _accounts.remove(target);
      await _storage.clearGoogleFor(target);
      final remaining = await _storage.googleAccounts();
      final updated = remaining.where((a) => a != target).toList();
      await _storage.saveGoogleAccounts(updated);
      _accounts
        ..clear()
        ..addAll(updated);
      if (_activeEmail == target) {
        _activeEmail = _accounts.isEmpty ? null : _accounts.first;
      }
      _initialized = false;
      return;
    }
    try {
      await GoogleSignIn.instance.signOut();
    } on UnimplementedError {
      // ignore
    } finally {
      _accessTokens.remove(target);
      _accounts.remove(target);
      await _storage.clearGoogleFor(target);
      final remaining = await _storage.googleAccounts();
      final updated = remaining.where((a) => a != target).toList();
      await _storage.saveGoogleAccounts(updated);
      _accounts
        ..clear()
        ..addAll(updated);
      if (_activeEmail == target) {
        _activeEmail = _accounts.isEmpty ? null : _accounts.first;
      }
      _initialized = false;
    }
  }

  Future<void> handleWebAccount(GoogleSignInAccount account) async {
    await _ensureInit();
    final email = account.email;
    if (!_accounts.contains(email)) _accounts.add(email);
    _activeEmail = email;
    final authz = await account.authorizationClient.authorizeScopes(
      AppConfig.googleScopes,
    );
    final token = authz.accessToken;
    _accessTokens[email] = token;
    await _storage.saveGoogleEmail(email);
    await _storage.saveGoogleTokensFor(
      account: email,
      accessToken: token,
      expiryMs: DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 50))
          .millisecondsSinceEpoch,
    );
    await _storage.saveGoogleAccounts(_accounts);
  }
}

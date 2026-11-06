part of '../google_auth.dart';

mixin _GoogleAuthToken on _GoogleAuthBase {
  Future<void> ensureTasksScope() async {
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows) {
      return;
    }
    await _ensureInit();
    final authz = await GoogleSignIn.instance.authorizationClient
        .authorizeScopes(AppConfig.googleScopes);
    final token = authz.accessToken;
    if (_activeEmail != null) _accessTokens[_activeEmail!] = token;
  }

  @override
  Future<String?> accessToken() async {
    final account = _activeEmail;
    if (account == null) return null;
    final cached = _accessTokens[account];
    if (cached != null) {
      final exp = await _storage.googleExpiryMsFor(account);
      if (exp == null || DateTime.now().toUtc().millisecondsSinceEpoch < exp) {
        return cached;
      }
    }
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows) {
      await _ensureInit();
      final storedAccess = await _storage.googleAccessTokenFor(account);
      final exp = await _storage.googleExpiryMsFor(account);
      if (storedAccess != null &&
          (exp == null ||
              DateTime.now().toUtc().millisecondsSinceEpoch < exp)) {
        _accessTokens[account] = storedAccess;
        return storedAccess;
      }
      final refresh = await _storage.googleRefreshTokenFor(account);
      if (refresh == null || AppConfig.linuxGoogleClientSecret.isEmpty) {
        return null;
      }
      final res = await HttpClient()
          .postUrl(Uri.parse('https://oauth2.googleapis.com/token'))
          .then((r) async {
            r.headers.contentType = ContentType(
              'application',
              'x-www-form-urlencoded',
            );
            final body =
                'client_id=${Uri.encodeQueryComponent(AppConfig.linuxGoogleClientId)}'
                '&client_secret=${Uri.encodeQueryComponent(AppConfig.linuxGoogleClientSecret)}'
                '&refresh_token=${Uri.encodeQueryComponent(refresh)}'
                '&grant_type=refresh_token';
            r.write(body);
            return r.close();
          });
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return null;
      final json = jsonDecode(body) as Map<String, dynamic>;
      final newAccess = json['access_token'] as String?;
      final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
      if (newAccess != null) {
        _accessTokens[account] = newAccess;
        await _storage.saveGoogleTokensFor(
          account: account,
          accessToken: newAccess,
          expiryMs: DateTime.now()
              .toUtc()
              .add(Duration(seconds: expiresIn - 60))
              .millisecondsSinceEpoch,
        );
      }
      return _accessTokens[account];
    }
    await _ensureInit();
    final authz = await GoogleSignIn.instance.authorizationClient
        .authorizationForScopes(AppConfig.googleScopes);
    if (authz == null) return null;
    _accessTokens[account] = authz.accessToken;
    await _storage.saveGoogleTokensFor(
      account: account,
      accessToken: authz.accessToken,
      expiryMs: DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 50))
          .millisecondsSinceEpoch,
    );
    return _accessTokens[account];
  }
}

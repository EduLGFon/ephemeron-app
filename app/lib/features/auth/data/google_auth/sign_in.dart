part of '../google_auth.dart';

mixin _GoogleAuthSignIn on _GoogleAuthBase {
  Future<String?> signIn({bool tasks = true}) async {
    debugPrint('GoogleAuth.signIn start platform=$defaultTargetPlatform');
    try {
      await _ensureInit();
    } on UnimplementedError {
      throw GoogleAuthException(
        'Google sign-in is not available on this platform. '
        'The app works fully offline without an account.',
      );
    }
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows) {
      try {
        return await _signInDesktop();
      } catch (e, st) {
        debugPrint('GoogleAuth desktop error: $e\n$st');
        rethrow;
      }
    }
    if (kIsWeb) {
      return _activeEmail;
    }
    try {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: tasks
            ? AppConfig.googleScopes
            : [AppConfig.googleScopes.first],
      );
      final email = account.email;
      final authz = await account.authorizationClient.authorizeScopes(
        _scopes(tasks),
      );
      final token = authz.accessToken;
      if (email.isEmpty) return _activeEmail;
      if (!_accounts.contains(email)) _accounts.add(email);
      _activeEmail = email;
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
      return _activeEmail;
    } on UnimplementedError {
      throw GoogleAuthException(
        'Google sign-in is not available on this platform. '
        'The app works fully offline without an account.',
      );
    }
  }

  Future<String?> _signInDesktop() async {
    final clientId = AppConfig.linuxGoogleClientId;
    final clientSecret = AppConfig.linuxGoogleClientSecret;
    if (clientId.isEmpty) {
      throw GoogleAuthException(
        'Google sign-in is not configured for desktop.',
      );
    }
    HttpServer? server;
    int port = 0;
    for (var p = 8085; p <= 8095; p++) {
      try {
        server = await HttpServer.bind('localhost', p);
        port = p;
        break;
      } catch (_) {
        continue;
      }
    }
    if (server == null) {
      throw GoogleAuthException('Could not start local sign-in server.');
    }
    final redirectUri = 'http://localhost:$port';
    final state = _randomString(32);
    final verifier = _randomString(64);
    final challenge = verifier;
    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': [...AppConfig.googleScopes, 'openid', 'email'].join(' '),
      'access_type': 'offline',
      'prompt': 'consent',
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'plain',
    }).toString();

    final codeCompleter = Completer<String>();
    server.listen((req) async {
      final code = req.uri.queryParameters['code'];
      final st = req.uri.queryParameters['state'];
      if (st != state) {
        req.response
          ..statusCode = 400
          ..write('State mismatch');
        await req.response.close();
        return;
      }
      if (code != null && !codeCompleter.isCompleted) {
        codeCompleter.complete(code);
      }
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<html><body>Signed in. You can close this window.</body></html>',
        );
      await req.response.close();
    });

    try {
      await Process.run('xdg-open', [authUrl]);
    } catch (_) {
      debugPrint('Open this URL to sign in: $authUrl');
    }

    final code = await codeCompleter.future.timeout(const Duration(minutes: 5));
    await server.close();

    final tokenReq = await HttpClient().postUrl(
      Uri.parse('https://oauth2.googleapis.com/token'),
    );
    tokenReq.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
    );
    final body =
        'code=${Uri.encodeQueryComponent(code)}'
        '&client_id=${Uri.encodeQueryComponent(clientId)}'
        '&client_secret=${Uri.encodeQueryComponent(clientSecret)}'
        '&redirect_uri=${Uri.encodeQueryComponent(redirectUri)}'
        '&grant_type=authorization_code'
        '&code_verifier=${Uri.encodeQueryComponent(verifier)}';
    tokenReq.write(body);
    final tokenRes = await tokenReq.close();
    final tokenBody = await tokenRes.transform(utf8.decoder).join();
    if (tokenRes.statusCode != 200) {
      throw GoogleAuthException('Token exchange failed: $tokenBody');
    }
    final tokenJson = jsonDecode(tokenBody) as Map<String, dynamic>;
    final accessToken = tokenJson['access_token'] as String;
    final refreshToken = tokenJson['refresh_token'] as String?;
    final expiresIn = (tokenJson['expires_in'] as num?)?.toInt() ?? 3600;
    final idToken = tokenJson['id_token'] as String?;

    String? email;
    try {
      final userReq = await HttpClient().getUrl(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
      );
      userReq.headers.set('Authorization', 'Bearer $accessToken');
      final userRes = await userReq.close();
      final userBody = await userRes.transform(utf8.decoder).join();
      if (userRes.statusCode == 200) {
        final userJson = jsonDecode(userBody) as Map<String, dynamic>;
        email = userJson['email'] as String?;
      }
    } catch (_) {}
    if (email == null && idToken != null) {
      final parts = idToken.split('.');
      if (parts.length == 3) {
        final payload =
            jsonDecode(
                  utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
                )
                as Map<String, dynamic>;
        email = payload['email'] as String?;
      }
    }
    if (email == null) return _activeEmail;
    if (!_accounts.contains(email)) _accounts.add(email);
    _activeEmail = email;
    _accessTokens[email] = accessToken;
    await _storage.saveGoogleEmail(email);
    await _storage.saveGoogleTokensFor(
      account: email,
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiryMs: DateTime.now()
          .toUtc()
          .add(Duration(seconds: expiresIn - 60))
          .millisecondsSinceEpoch,
    );
    await _storage.saveGoogleAccounts(_accounts);
    return _activeEmail;
  }
}

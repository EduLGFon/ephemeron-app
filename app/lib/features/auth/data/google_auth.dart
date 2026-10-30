// Google sign-in (v7 API on mobile/web): incremental scopes, silent token refresh.
// Google tokens live in memory + keystore; they never touch our backend.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/safe_storage.dart';

class GoogleAuthException implements Exception {
  GoogleAuthException(this.message);
  final String message;
  @override
  String toString() => 'GoogleAuthException: $message';
}

class GoogleAuth {
  GoogleAuth({SafeSecureStorage? storage})
    : _storage = storage ?? SafeSecureStorage();

  final SafeSecureStorage _storage;
  bool _initialized = false;
  String? _email;
  String? _accessToken;

  String? get email => _email;
  bool get isSignedIn => _email != null;

  /// Restores a previous sign-in after restart. Returns the email when
  /// stored credentials are still usable, null otherwise (and forgets
  /// dead credentials so the UI shows signed-out).
  Future<String?> restore() async {
    final email = await _storage.googleEmail;
    if (email == null || email.isEmpty) return null;
    try {
      await _ensureInit();
      final token = await accessToken();
      if (token == null) {
        await _storage.clearGoogle();
        return null;
      }
      _email = email;
      debugPrint('GoogleAuth.restore ok email=$_email');
      return _email;
    } catch (e) {
      debugPrint('GoogleAuth.restore failed: $e');
      return null;
    }
  }

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
      // Desktop uses loopback OAuth; no google_sign_in init needed.
      _initialized = true;
      return;
    }
    try {
      await GoogleSignIn.instance.initialize(
        clientId: defaultTargetPlatform == TargetPlatform.android
            ? (AppConfig.androidGoogleClientId.isEmpty
                  ? null
                  : AppConfig.androidGoogleClientId)
            : (AppConfig.webGoogleClientId.isEmpty
                  ? null
                  : AppConfig.webGoogleClientId),
      );
    } on UnimplementedError {
      throw GoogleAuthException(
        'Google sign-in is not available on this platform. '
        'The app works fully offline without an account.',
      );
    }
    _initialized = true;
  }

  Future<String?> signIn({bool tasks = false}) async {
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
      // Web uses the rendered button; signIn is a no-op fallback.
      return _email;
    }
    try {
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
      if (_email != null) await _storage.saveGoogleEmail(_email!);
      await _storage.saveGoogleTokens(
        accessToken: _accessToken!,
        expiryMs: DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 50))
            .millisecondsSinceEpoch,
      );
      return _email;
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
    // Find a free loopback port.
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
      // Fallback: print URL.
      // ignore: avoid_print
      print('Open this URL to sign in: $authUrl');
    }

    final code = await codeCompleter.future.timeout(const Duration(minutes: 5));
    debugPrint('GoogleAuth desktop got code');
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

    // Fetch user email.
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
    _email = email;
    _accessToken = accessToken;
    debugPrint('GoogleAuth desktop email=$_email');
    if (email != null) await _storage.saveGoogleEmail(email);
    await _storage.saveGoogleTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiryMs: DateTime.now()
          .toUtc()
          .add(Duration(seconds: expiresIn - 60))
          .millisecondsSinceEpoch,
    );
    return _email;
  }

  Future<void> ensureTasksScope() async {
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows) {
      return;
    }
    await _ensureInit();
    final authz = await GoogleSignIn.instance.authorizationClient
        .authorizeScopes(AppConfig.googleScopes);
    _accessToken = authz.accessToken;
  }

  Future<String?> accessToken() async {
    if (_accessToken != null) {
      final exp = await _storage.googleExpiryMs;
      if (exp == null || DateTime.now().toUtc().millisecondsSinceEpoch < exp) {
        return _accessToken;
      }
    }
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows) {
      await _ensureInit();
      final storedAccess = await _storage.googleAccessToken;
      final exp = await _storage.googleExpiryMs;
      if (storedAccess != null &&
          (exp == null ||
              DateTime.now().toUtc().millisecondsSinceEpoch < exp)) {
        _accessToken = storedAccess;
        return _accessToken;
      }
      final refresh = await _storage.googleRefreshToken;
      if (refresh == null || AppConfig.linuxGoogleClientSecret.isEmpty) {
        debugPrint(
          '[sync] desktop token expired and no refresh available '
          '(hasRefresh=${refresh != null}): re-sign-in required',
        );
        return null;
      }
      debugPrint('[sync] desktop token expired, refreshing');
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
      if (res.statusCode != 200) {
        debugPrint(
          '[sync] desktop token refresh failed status=${res.statusCode}',
        );
        return null;
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final newAccess = json['access_token'] as String?;
      final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
      if (newAccess != null) {
        _accessToken = newAccess;
        await _storage.saveGoogleTokens(
          accessToken: newAccess,
          expiryMs: DateTime.now()
              .toUtc()
              .add(Duration(seconds: expiresIn - 60))
              .millisecondsSinceEpoch,
        );
      }
      return _accessToken;
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
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows) {
      _email = null;
      _accessToken = null;
      await _storage.clearGoogle();
      _initialized = false;
      return;
    }
    try {
      await GoogleSignIn.instance.signOut();
    } on UnimplementedError {
      // No-op on platforms without a plugin implementation.
    } finally {
      _email = null;
      _accessToken = null;
      await _storage.clearGoogle();
      _initialized = false;
    }
  }

  Future<void> handleWebAccount(GoogleSignInAccount account) async {
    debugPrint('handleWebAccount start');
    await _ensureInit();
    _email = account.email;
    if (_email != null) await _storage.saveGoogleEmail(_email!);
    final authz = await account.authorizationClient.authorizeScopes(
      AppConfig.googleScopes,
    );
    _accessToken = authz.accessToken;
    await _storage.saveGoogleTokens(
      accessToken: _accessToken!,
      expiryMs: DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 50))
          .millisecondsSinceEpoch,
    );
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

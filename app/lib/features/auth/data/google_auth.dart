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
      return _signInDesktop();
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
      throw GoogleAuthException('Google sign-in is not configured for desktop.');
    }
    // Find a free loopback port.
    HttpServer? server;
    int port = 0;
    for (var p = 8085; p <= 8095; p++) {
      try {
        server = await HttpServer.bind('127.0.0.1', p);
        port = p;
        break;
      } catch (_) {
        continue;
      }
    }
    if (server == null) {
      throw GoogleAuthException('Could not start local sign-in server.');
    }
    final redirectUri = 'http://127.0.0.1:$port';
    final state = _randomString(32);
    final verifier = _randomString(64);
    final challenge = verifier;
    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': AppConfig.googleScopes.join(' '),
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
      if (code != null) {
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
    await server.close();

    final tokenRes = await HttpClient()
        .postUrl(Uri.parse('https://oauth2.googleapis.com/token'))
        .then((r) async {
          r.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
          final body =
              'code=${Uri.encodeQueryComponent(code)}'
              '&client_id=${Uri.encodeQueryComponent(clientId)}'
              '&client_secret=${Uri.encodeQueryComponent(clientSecret)}'
              '&redirect_uri=${Uri.encodeQueryComponent(redirectUri)}'
              '&grant_type=authorization_code'
              '&code_verifier=${Uri.encodeQueryComponent(verifier)}';
          r.write(body);
          return r.close();
        });
    final tokenBody = await tokenRes.transform(utf8.decoder).join();
    final tokenJson = jsonDecode(tokenBody) as Map<String, dynamic>;
    final accessToken = tokenJson['access_token'] as String;
    final refreshToken = tokenJson['refresh_token'] as String?;
    final expiresIn = (tokenJson['expires_in'] as num?)?.toInt() ?? 3600;

    // Fetch user email.
    final userRes = await HttpClient()
        .getUrl(Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'))
        .then((r) async {
          r.headers.set('Authorization', 'Bearer $accessToken');
          return r.close();
        });
    final userBody = await userRes.transform(utf8.decoder).join();
    final userJson = jsonDecode(userBody) as Map<String, dynamic>;
    _email = userJson['email'] as String?;
    _accessToken = accessToken;
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
      if (exp == null ||
          DateTime.now().toUtc().millisecondsSinceEpoch < exp) {
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
        return storedAccess;
      }
      final res = await HttpClient()
          .postUrl(Uri.parse('https://oauth2.googleapis.com/token'))
          .then((r) async {
            r.headers.contentType =
                ContentType('application', 'x-www-form-urlencoded');
            final body =
                'client_id=${Uri.encodeQueryComponent(AppConfig.linuxGoogleClientId)}'
                '&client_secret=${Uri.encodeQueryComponent(AppConfig.linuxGoogleClientSecret)}'
                '&refresh_token=${Uri.encodeQueryComponent(refresh)}'
                '&grant_type=refresh_token';
            r.write(body);
            return r.close();
          });
      final body = await res.transform(utf8.decoder).join();
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
    await _ensureInit();
    _email = account.email;
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
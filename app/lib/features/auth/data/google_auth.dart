// Google sign-in (v7 API on mobile/web): incremental scopes, silent token refresh.
// Supports multiple signed-in accounts simultaneously.
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
  final List<String> _accounts = [];
  String? _activeEmail;
  final Map<String, String?> _accessTokens = {};

  List<String> get accounts => List.unmodifiable(_accounts);
  String? get email => _activeEmail;
  bool get isSignedIn => _activeEmail != null && _accounts.isNotEmpty;

  Future<void> setActiveAccount(String email) async {
    if (_accounts.contains(email)) _activeEmail = email;
  }

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
      // ignore
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

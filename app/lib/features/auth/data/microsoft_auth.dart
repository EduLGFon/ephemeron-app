// Microsoft (Entra ID) sign-in via OAuth2 authorization code + PKCE.
// Public client only: no client secret. Tokens live in SafeSecureStorage.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart' as oauth2;

import '../../../core/config/app_config.dart';
import '../../../core/config/safe_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

class MicrosoftAuthException implements Exception {
  MicrosoftAuthException(this.message);
  final String message;
  @override
  String toString() => 'MicrosoftAuthException: $message';
}

typedef MicrosoftWebLauncher =
    Future<String> Function(String url, String callbackUrlScheme);

class MicrosoftAuth {
  MicrosoftAuth({
    SafeSecureStorage? storage,
    http.Client? httpClient,
    MicrosoftWebLauncher? launcher,
  }) : _storage = storage ?? SafeSecureStorage(),
       _http = httpClient ?? http.Client(),
       _launcher = launcher ?? _defaultLauncher;

  final SafeSecureStorage _storage;
  final http.Client _http;
  final MicrosoftWebLauncher _launcher;

  static Future<String> _defaultLauncher(String url, String scheme) =>
      FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: scheme);

  final List<String> _accounts = [];
  String? _activeEmail;
  final Map<String, oauth2.Credentials> _creds = {};

  List<String> get accounts => List.unmodifiable(_accounts);
  String? get activeEmail => _activeEmail;

  Uri get _authorizationEndpoint =>
      Uri.parse('${AppConfig.microsoftAuthority}/oauth2/v2.0/authorize');
  Uri get _tokenEndpoint =>
      Uri.parse('${AppConfig.microsoftAuthority}/oauth2/v2.0/token');

  Future<String?> restore() async {
    final accs = await _storage.microsoftAccounts();
    _accounts
      ..clear()
      ..addAll(accs);
    final active = await _storage.microsoftActiveAccount();
    if (active != null && _accounts.contains(active)) {
      _activeEmail = active;
    } else if (_accounts.isNotEmpty) {
      _activeEmail = _accounts.first;
    } else {
      _activeEmail = null;
    }
    return _activeEmail;
  }

  Future<void> setActiveAccount(String email) async {
    if (_accounts.isEmpty) {
      _accounts.addAll(await _storage.microsoftAccounts());
    }
    if (_accounts.contains(email)) {
      _activeEmail = email;
      await _storage.saveMicrosoftActiveAccount(email);
    }
  }

  Future<String?> signIn() async {
    if (AppConfig.microsoftClientId.isEmpty) {
      throw MicrosoftAuthException('Microsoft sign-in is not configured.');
    }
    final redirectUri = kIsWeb
        ? AppConfig.microsoftWebRedirectUri
        : AppConfig.microsoftNativeRedirectUri;
    final redirect = Uri.parse(redirectUri);
    final callbackScheme = redirect.scheme;

    final state = _randomString(32);
    final grant = oauth2.AuthorizationCodeGrant(
      AppConfig.microsoftClientId,
      _authorizationEndpoint,
      _tokenEndpoint,
      secret: null,
      httpClient: _http,
    );

    final authUrl = grant.getAuthorizationUrl(
      redirect,
      scopes: AppConfig.microsoftScopes,
      state: state,
    );

    String callback;
    try {
      callback = await _launcher(authUrl.toString(), callbackScheme);
    } catch (e) {
      throw MicrosoftAuthException('Sign-in was cancelled or failed.');
    }

    final params = Uri.parse(callback).queryParameters;
    oauth2.Client client;
    try {
      client = await grant.handleAuthorizationResponse(params);
    } on FormatException {
      throw MicrosoftAuthException('State validation failed.');
    } catch (e) {
      throw MicrosoftAuthException('Token exchange failed.');
    }

    final creds = client.credentials;
    final accessToken = creds.accessToken;
    if (accessToken.isEmpty) {
      throw MicrosoftAuthException('Token exchange failed.');
    }
    final refreshToken = creds.refreshToken;
    final expiryMs =
        creds.expiration?.millisecondsSinceEpoch ??
        DateTime.now().toUtc().millisecondsSinceEpoch + 3600000;

    // Resolve identity from Graph.
    final res = await _http.get(
      Uri.parse(
        '${AppConfig.microsoftGraphBase}/me?\$select=id,displayName,mail,userPrincipalName',
      ),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (res.statusCode != 200) {
      throw MicrosoftAuthException('Failed to load account identity.');
    }
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('bad json');
      }
      json = decoded;
    } catch (_) {
      throw MicrosoftAuthException('Failed to load account identity.');
    }
    final email = (json['mail'] ?? json['userPrincipalName'])?.toString();
    if (email == null || email.isEmpty) {
      throw MicrosoftAuthException('Account has no email address.');
    }

    final storedAccounts = await _storage.microsoftAccounts();
    for (final a in storedAccounts) {
      if (!_accounts.contains(a)) _accounts.add(a);
    }
    if (!_accounts.contains(email)) _accounts.add(email);
    _activeEmail = email;
    _creds[email] = creds;
    await _storage.saveMicrosoftAccounts(_accounts);
    await _storage.saveMicrosoftActiveAccount(email);
    await _storage.saveMicrosoftTokensFor(
      account: email,
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiryMs: expiryMs,
    );
    return email;
  }

  Future<String?> accessToken() async {
    final account = _activeEmail;
    if (account == null) return null;
    final creds = _creds[account];
    final storedAccess = await _storage.microsoftAccessTokenFor(account);
    final storedRefresh = await _storage.microsoftRefreshTokenFor(account);
    final storedExpiry = await _storage.microsoftExpiryMsFor(account);

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (storedAccess != null &&
        (storedExpiry == null || now < storedExpiry) &&
        (creds == null || !creds.isExpired)) {
      _creds.putIfAbsent(
        account,
        () => oauth2.Credentials(
          storedAccess,
          refreshToken: storedRefresh,
          tokenEndpoint: _tokenEndpoint,
          expiration: storedExpiry == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(storedExpiry),
        ),
      );
      return storedAccess;
    }

    if (storedRefresh == null) {
      return storedAccess;
    }

    try {
      final baseCreds =
          creds ??
          oauth2.Credentials(
            storedAccess ?? '',
            refreshToken: storedRefresh,
            tokenEndpoint: _tokenEndpoint,
            expiration: storedExpiry == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(storedExpiry),
          );
      final newCreds = await baseCreds.refresh(
        identifier: AppConfig.microsoftClientId,
        httpClient: _http,
      );
      final newAccess = newCreds.accessToken;
      final newRefresh = newCreds.refreshToken ?? storedRefresh;
      final newExpiry =
          newCreds.expiration?.millisecondsSinceEpoch ?? now + 3600000;
      _creds[account] = newCreds;
      await _storage.saveMicrosoftTokensFor(
        account: account,
        accessToken: newAccess,
        refreshToken: newRefresh,
        expiryMs: newExpiry,
      );
      return newAccess;
    } catch (_) {
      return null;
    }
  }

  Future<void> signOut(String? account) async {
    final target = account ?? _activeEmail;
    if (target == null) return;
    if (_accounts.isEmpty) {
      _accounts.addAll(await _storage.microsoftAccounts());
    }
    _creds.remove(target);
    _accounts.remove(target);
    await _storage.clearMicrosoftFor(target);
    final remaining = await _storage.microsoftAccounts();
    final updated = remaining.where((a) => a != target).toList();
    await _storage.saveMicrosoftAccounts(updated);
    _accounts
      ..clear()
      ..addAll(updated);
    if (_activeEmail == target) {
      _activeEmail = _accounts.isEmpty ? null : _accounts.first;
    }
    await _storage.saveMicrosoftActiveAccount(_activeEmail);
  }

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

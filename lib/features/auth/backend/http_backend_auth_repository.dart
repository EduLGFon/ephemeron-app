import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import 'backend_auth_repository.dart';
import 'secure_token_storage.dart';

class HttpBackendAuthRepository implements BackendAuthRepository {
  HttpBackendAuthRepository({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  final _sessionController = StreamController<BackendSession?>.broadcast();
  BackendSession? _currentSession;

  @override
  Stream<BackendSession?> get sessionChanges => _sessionController.stream;

  @override
  BackendSession? get currentSession => _currentSession;

  @override
  Future<void> restoreSession() async {
    final stored = await SecureTokenStorage.readSession();
    if (stored == null) return;

    // The access token itself is never persisted (see
    // SecureTokenStorage's doc comment) — mint a fresh one immediately
    // using the stored refresh token instead of trusting a stale one.
    try {
      final refreshed = await _refreshAccessToken(stored.refreshToken);
      _currentSession = BackendSession(
        userId: stored.userId,
        email: stored.email,
        accessToken: refreshed.accessToken,
        refreshToken: stored.refreshToken,
        accessTokenExpiresAt: refreshed.expiresAt,
      );
      _sessionController.add(_currentSession);
    } on BackendAuthException {
      // Refresh token is dead (expired/revoked) — treat as signed out
      // rather than surfacing an error on cold start.
      await SecureTokenStorage.clear();
      _currentSession = null;
      _sessionController.add(null);
    }
  }

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {
    final body = await _post('/auth/register', {
      'email': email,
      'password': password,
    });
    await _applyAuthResponse(email: email, body: body);
  }

  @override
  Future<void> login({required String email, required String password}) async {
    final body = await _post('/auth/login', {
      'email': email,
      'password': password,
    });
    await _applyAuthResponse(email: email, body: body);
  }

  @override
  Future<void> logout() async {
    final session = _currentSession;
    if (session != null) {
      // Best-effort — don't block local sign-out on this succeeding.
      unawaited(
        _post('/auth/logout', {'refreshToken': session.refreshToken})
            .catchError((_) => <String, dynamic>{}),
      );
    }
    await SecureTokenStorage.clear();
    _currentSession = null;
    _sessionController.add(null);
  }

  @override
  Future<String> getValidAccessToken() async {
    final session = _currentSession;
    if (session == null) {
      throw const BackendAuthException('Not logged in.');
    }
    if (!session.isAccessTokenExpired) return session.accessToken;

    final refreshed = await _refreshAccessToken(session.refreshToken);
    _currentSession = session.copyWithAccessToken(
      accessToken: refreshed.accessToken,
      expiresAt: refreshed.expiresAt,
    );
    _sessionController.add(_currentSession);
    return refreshed.accessToken;
  }

  Future<void> _applyAuthResponse({
    required String email,
    required Map<String, dynamic> body,
  }) async {
    final userId = body['userId'] as String;
    final accessToken = body['accessToken'] as String;
    final refreshToken = body['refreshToken'] as String;
    final expiresIn = body['expiresIn'] as int;

    await SecureTokenStorage.saveSession(
      refreshToken: refreshToken,
      userId: userId,
      email: email,
    );

    _currentSession = BackendSession(
      userId: userId,
      email: email,
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessTokenExpiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
    _sessionController.add(_currentSession);
  }

  Future<({String accessToken, DateTime expiresAt})> _refreshAccessToken(
    String refreshToken,
  ) async {
    final body = await _post('/auth/refresh', {'refreshToken': refreshToken});
    final accessToken = body['accessToken'] as String;
    final expiresIn = body['expiresIn'] as int;
    return (
      accessToken: accessToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('${AppConfig.backendBaseUrl}$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } on Exception catch (e) {
      throw BackendAuthException('Could not reach the server: $e');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    String message = 'Request failed (${response.statusCode}).';
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['message'] is String) message = decoded['message'] as String;
    } catch (_) {
      // Body wasn't JSON — fall back to the generic message above.
    }
    throw BackendAuthException(message, statusCode: response.statusCode);
  }
}

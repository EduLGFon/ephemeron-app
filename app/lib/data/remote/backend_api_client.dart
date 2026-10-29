// Backend authentication REST client (own VPS, habits/focus data only).
// Google tokens, events and tasks never touch this backend (enforced by
// construction: this client only sends email/password and habit/focus
// payloads). TLS default; no token logging.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';

class BackendApiException implements Exception {
  BackendApiException(this.status, this.message, {this.retryAfterSec});

  final int status;
  final String message;
  final int? retryAfterSec;

  bool get isUnauthorized => status == 401;
  bool get isRateLimited => status == 429;
}

class BackendSession {
  BackendSession({
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAtMs,
  });

  final String email;
  final String accessToken;
  final String refreshToken;
  final int expiresAtMs;
}

/// Auth endpoints only. Changeset sync lives in the backend sync engine.
abstract class BackendApiClient {
  Future<BackendSession> register(String email, String password);
  Future<BackendSession> login(String email, String password);
  Future<BackendSession> refresh(String refreshToken);
  Future<void> logout(String refreshToken);
  Future<void> deleteAccount(String accessToken);
}

class HttpBackendApiClient implements BackendApiClient {
  HttpBackendApiClient({http.Client? httpClient, String? baseUrl})
    : _http = httpClient ?? http.Client(),
      _base = baseUrl ?? AppConfig.backendBaseUrl;

  final http.Client _http;
  final String _base;

  Map<String, String> get _json => {'Content-Type': 'application/json'};

  BackendSession _sessionOf(Map<String, dynamic> json) {
    return BackendSession(
      email: json['email'] as String,
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresAtMs:
          DateTime.now().toUtc().millisecondsSinceEpoch +
          ((json['expiresInSec'] as int? ?? 900) * 1000),
    );
  }

  Never _throw(int status, String body, {int? retryAfterSec}) {
    var message = 'backend $status';
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final m = json['message'] ?? json['error'];
      if (m is String && m.isNotEmpty) message = m;
    } catch (_) {}
    throw BackendApiException(status, message, retryAfterSec: retryAfterSec);
  }

  int? _retryAfter(Map<String, String> headers) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == 'retry-after') return int.tryParse(e.value);
    }
    return null;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async {
    final headers = Map<String, String>.of(_json);
    if (accessToken != null) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    final res = await _http.post(
      Uri.parse('$_base$path'),
      headers: headers,
      body: jsonEncode(body),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throw(res.statusCode, res.body, retryAfterSec: _retryAfter(res.headers));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  @override
  Future<BackendSession> register(String email, String password) async {
    return _sessionOf(
      await _post('/auth/register', {'email': email, 'password': password}),
    );
  }

  @override
  Future<BackendSession> login(String email, String password) async {
    return _sessionOf(
      await _post('/auth/login', {'email': email, 'password': password}),
    );
  }

  @override
  Future<BackendSession> refresh(String refreshToken) async {
    return _sessionOf(
      await _post('/auth/refresh', {'refreshToken': refreshToken}),
    );
  }

  @override
  Future<void> logout(String refreshToken) async {
    await _post('/auth/logout', {'refreshToken': refreshToken});
  }

  @override
  Future<void> deleteAccount(String accessToken) async {
    final res = await _http.delete(
      Uri.parse('$_base/account'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throw(res.statusCode, res.body, retryAfterSec: _retryAfter(res.headers));
    }
  }
}

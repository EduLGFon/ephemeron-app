// Backend changeset sync API (habits + focus only).
// Google data never touches this client: payloads are habit/focus rows.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import 'backend_api_client.dart';

class BackendPull {
  BackendPull({
    required this.habits,
    required this.habitLogs,
    required this.focusSessions,
  });

  final List<Map<String, dynamic>> habits;
  final List<Map<String, dynamic>> habitLogs;
  final List<Map<String, dynamic>> focusSessions;
}

abstract class BackendSyncApi {
  Future<void> push({
    required List<Map<String, dynamic>> habits,
    required List<Map<String, dynamic>> habitLogs,
    required List<Map<String, dynamic>> focusSessions,
  });
  Future<BackendPull> pull(int sinceMs);
}

class HttpBackendSyncApi implements BackendSyncApi {
  HttpBackendSyncApi({
    http.Client? httpClient,
    String? baseUrl,
    required Future<String?> Function() accessToken,
  }) : _http = httpClient ?? http.Client(),
       _base = baseUrl ?? AppConfig.backendBaseUrl,
       _accessToken = accessToken;

  final http.Client _http;
  final String _base;
  final Future<String?> Function() _accessToken;

  Future<Map<String, String>> _headers() async {
    final token = await _accessToken();
    if (token == null) throw BackendApiException(401, 'Not signed in.');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Never _throw(int status, String body, Map<String, String> headers) {
    var message = 'backend $status';
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final m = json['message'] ?? json['error'];
      if (m is String && m.isNotEmpty) message = m;
    } catch (_) {}
    int? retryAfter;
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == 'retry-after') {
        retryAfter = int.tryParse(e.value);
      }
    }
    throw BackendApiException(status, message, retryAfterSec: retryAfter);
  }

  @override
  Future<void> push({
    required List<Map<String, dynamic>> habits,
    required List<Map<String, dynamic>> habitLogs,
    required List<Map<String, dynamic>> focusSessions,
  }) async {
    final res = await _http.post(
      Uri.parse('$_base/sync/push'),
      headers: await _headers(),
      body: jsonEncode({
        'habits': habits,
        'habitLogs': habitLogs,
        'focusSessions': focusSessions,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throw(res.statusCode, res.body, res.headers);
    }
  }

  @override
  Future<BackendPull> pull(int sinceMs) async {
    final res = await _http.get(
      Uri.parse('$_base/sync/pull?since=$sinceMs'),
      headers: await _headers(),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _throw(res.statusCode, res.body, res.headers);
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    List<Map<String, dynamic>> list(String key) =>
        ((json[key] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
    return BackendPull(
      habits: list('habits'),
      habitLogs: list('habitLogs'),
      focusSessions: list('focusSessions'),
    );
  }
}

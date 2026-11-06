part of '../google_api_client.dart';

abstract class _GoogleApiBase implements GoogleApiClient {
  _GoogleApiBase({
    required Future<String?> Function() accessToken,
    http.Client? httpClient,
  }) : _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  final Future<String?> Function() _accessToken;
  final http.Client _http;

  Future<Map<String, String>> _headers({String? etag}) async {
    final token = await _accessToken();
    if (token == null) throw GoogleApiException(401, 'no token');
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    if (etag != null) headers['If-Match'] = etag;
    return headers;
  }

  Never _throw(http.Response r) {
    int? retry;
    final ra = r.headers['retry-after'];
    if (ra != null) retry = int.tryParse(ra);
    throw GoogleApiException(r.statusCode, r.body, retryAfterSec: retry);
  }
}

import 'package:http/http.dart' as http;

/// Wraps an [http.Client] to inject `Authorization: Bearer <token>` on
/// every request, sourcing the token from [tokenProvider] fresh on each
/// call rather than caching it here — this keeps the client agnostic to
/// *where* the token comes from (Google's authorizationClient, or our own
/// backend's stored access token) and to how it's refreshed.
///
/// Deliberately does not implement automatic 401-retry-with-refresh here:
/// that behavior differs enough between the Google and backend cases
/// (Google's web tokens simply expire and need a new interactive
/// authorization round; the backend case can silently refresh via a
/// refresh token) that each repository handles its own 401 recovery
/// rather than this shared client guessing at one policy for both.
class BearerHttpClient extends http.BaseClient {
  BearerHttpClient({required this.tokenProvider, http.Client? inner})
      : _inner = inner ?? http.Client();

  final Future<String?> Function() tokenProvider;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = await tokenProvider();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

// Backend account session: email/password auth for habits/focus sync.
// Access tokens stay in memory; only the rotating refresh token is
// persisted via the token store (secure storage in production).
// PRIVACY: never log tokens or passwords.
import '../../../core/config/safe_storage.dart';
import '../../../data/remote/backend_api_client.dart';

/// Refresh-token persistence seam: production uses the platform keystore,
/// tests use an in-memory fake.
abstract class BackendTokenStore {
  Future<void> saveRefresh(String token);
  Future<String?> readRefresh();
  Future<void> clear();
}

class SecureBackendTokenStore implements BackendTokenStore {
  SecureBackendTokenStore({SafeSecureStorage? storage})
    : _storage = storage ?? SafeSecureStorage();

  final SafeSecureStorage _storage;

  @override
  Future<void> saveRefresh(String token) => _storage.saveBackendRefresh(token);

  @override
  Future<String?> readRefresh() => _storage.backendRefreshToken;

  @override
  Future<void> clear() => _storage.clearBackend();
}

class BackendAuth {
  BackendAuth({BackendApiClient? client, BackendTokenStore? tokenStore})
    : _client = client ?? HttpBackendApiClient(),
      _tokens = tokenStore ?? SecureBackendTokenStore();

  final BackendApiClient _client;
  final BackendTokenStore _tokens;
  String? _email;
  String? _accessToken;
  int? _accessExpiryMs;

  String? get email => _email;
  bool get isSignedIn => _email != null;

  void _validate(String email, String password) {
    if (!email.contains('@')) throw BackendApiException(400, 'Invalid email.');
    if (password.length < 8) {
      throw BackendApiException(400, 'Password needs 8+ characters.');
    }
  }

  Future<void> _adopt(BackendSession s) async {
    _email = s.email;
    _accessToken = s.accessToken;
    _accessExpiryMs = s.expiresAtMs;
    await _tokens.saveRefresh(s.refreshToken);
  }

  Future<String> signUp(String email, String password) async {
    _validate(email, password);
    await _adopt(await _client.register(email, password));
    return _email!;
  }

  Future<String> login(String email, String password) async {
    _validate(email, password);
    await _adopt(await _client.login(email, password));
    return _email!;
  }

  /// Restores a previous session from the stored refresh token.
  Future<String?> restore() async {
    final refreshToken = await _tokens.readRefresh();
    if (refreshToken == null) return null;
    try {
      await _adopt(await _client.refresh(refreshToken));
    } on BackendApiException {
      await _tokens.clear();
      return null;
    }
    return _email;
  }

  /// Valid access token, refreshing silently when expired.
  Future<String?> accessToken() async {
    if (_accessToken != null &&
        _accessExpiryMs != null &&
        DateTime.now().toUtc().millisecondsSinceEpoch < _accessExpiryMs!) {
      return _accessToken;
    }
    return restore();
  }

  Future<void> signOut() async {
    final refreshToken = await _tokens.readRefresh();
    if (refreshToken != null) {
      try {
        await _client.logout(refreshToken);
      } on BackendApiException {
        // Still clear local state; the refresh token rotates server-side.
      }
    }
    _email = null;
    _accessToken = null;
    _accessExpiryMs = null;
    await _tokens.clear();
  }

  /// LGPD deletion: removes remote data, offers export first in the UI.
  Future<void> deleteAccount() async {
    final token = await accessToken();
    if (token == null) throw BackendApiException(401, 'Not signed in.');
    await _client.deleteAccount(token);
    _email = null;
    _accessToken = null;
    _accessExpiryMs = null;
    await _tokens.clear();
  }
}

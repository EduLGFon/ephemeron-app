// Token storage. Backend/Google refresh tokens live ONLY here
// (flutter_secure_storage + platform keystore), never SharedPreferences.
// PRIVACY: never log token values.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SafeSecureStorage {
  SafeSecureStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kGoogleAccess = 'google.accessToken';
  static const _kGoogleRefresh = 'google.refreshToken';
  static const _kGoogleExpiry = 'google.expiryMs';
  static const _kBackendRefresh = 'backend.refreshToken';

  Future<void> saveGoogleTokens({
    required String accessToken,
    String? refreshToken,
    required int expiryMs,
  }) async {
    await _storage.write(key: _kGoogleAccess, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: _kGoogleRefresh, value: refreshToken);
    }
    await _storage.write(key: _kGoogleExpiry, value: expiryMs.toString());
  }

  Future<String?> get googleAccessToken => _storage.read(key: _kGoogleAccess);
  Future<String?> get googleRefreshToken => _storage.read(key: _kGoogleRefresh);
  Future<int?> get googleExpiryMs async {
    final v = await _storage.read(key: _kGoogleExpiry);
    return v == null ? null : int.tryParse(v);
  }

  Future<void> clearGoogle() async {
    await _storage.delete(key: _kGoogleAccess);
    await _storage.delete(key: _kGoogleRefresh);
    await _storage.delete(key: _kGoogleExpiry);
  }

  Future<void> saveBackendRefresh(String token) =>
      _storage.write(key: _kBackendRefresh, value: token);
  Future<String?> get backendRefreshToken =>
      _storage.read(key: _kBackendRefresh);
  Future<void> clearBackend() => _storage.delete(key: _kBackendRefresh);
}

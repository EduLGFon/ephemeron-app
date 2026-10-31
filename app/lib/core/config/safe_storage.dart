// Safe wrapper around flutter_secure_storage. All secrets live here.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SafeSecureStorage {
  SafeSecureStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kAccounts = 'google.accounts';
  String _a(String account, String key) => 'google.$account.$key';

  Future<List<String>> googleAccounts() async {
    final v = await _storage.read(key: _kAccounts);
    if (v == null || v.isEmpty) return const [];
    return v.split(',').where((e) => e.isNotEmpty).toList();
  }

  Future<void> saveGoogleAccounts(List<String> accounts) async {
    await _storage.write(key: _kAccounts, value: accounts.join(','));
  }

  Future<void> saveGoogleTokensFor({
    required String account,
    required String accessToken,
    String? refreshToken,
    required int expiryMs,
  }) async {
    await _storage.write(key: _a(account, 'accessToken'), value: accessToken);
    if (refreshToken != null) {
      await _storage.write(
        key: _a(account, 'refreshToken'),
        value: refreshToken,
      );
    }
    await _storage.write(
      key: _a(account, 'expiryMs'),
      value: expiryMs.toString(),
    );
  }

  Future<String?> googleAccessTokenFor(String account) =>
      _storage.read(key: _a(account, 'accessToken'));

  Future<String?> googleRefreshTokenFor(String account) =>
      _storage.read(key: _a(account, 'refreshToken'));

  Future<int?> googleExpiryMsFor(String account) async {
    final v = await _storage.read(key: _a(account, 'expiryMs'));
    if (v == null) return null;
    return int.tryParse(v);
  }

  Future<void> clearGoogleFor(String account) async {
    await _storage.delete(key: _a(account, 'accessToken'));
    await _storage.delete(key: _a(account, 'refreshToken'));
    await _storage.delete(key: _a(account, 'expiryMs'));
  }

  // Legacy single-account helpers (delegate to a default account key).
  Future<String?> get googleEmail async {
    final accs = await googleAccounts();
    return accs.isEmpty ? null : accs.first;
  }

  Future<void> saveGoogleEmail(String email) async {
    final accs = await googleAccounts();
    if (!accs.contains(email)) {
      await saveGoogleAccounts([...accs, email]);
    }
  }

  Future<String?> get googleAccessToken async {
    final e = await googleEmail;
    if (e == null) return null;
    return googleAccessTokenFor(e);
  }

  Future<String?> get googleRefreshToken async {
    final e = await googleEmail;
    if (e == null) return null;
    return googleRefreshTokenFor(e);
  }

  Future<int?> get googleExpiryMs async {
    final e = await googleEmail;
    if (e == null) return null;
    return googleExpiryMsFor(e);
  }

  Future<void> saveGoogleTokens({
    required String accessToken,
    String? refreshToken,
    required int expiryMs,
  }) async {
    final e = await googleEmail;
    if (e == null) return;
    await saveGoogleTokensFor(
      account: e,
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiryMs: expiryMs,
    );
  }

  // Backend helpers (single account).
  static const _kBackendAccess = 'backend.accessToken';
  static const _kBackendRefresh = 'backend.refreshToken';

  Future<void> saveBackendTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _storage.write(key: _kBackendAccess, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: _kBackendRefresh, value: refreshToken);
    }
  }

  Future<String?> get backendAccessToken => _storage.read(key: _kBackendAccess);
  Future<String?> get backendRefreshToken =>
      _storage.read(key: _kBackendRefresh);
  Future<void> saveBackendRefresh(String token) =>
      _storage.write(key: _kBackendRefresh, value: token);

  Future<void> clearBackend() async {
    await _storage.delete(key: _kBackendAccess);
    await _storage.delete(key: _kBackendRefresh);
  }

  Future<void> clearGoogle() async {
    final accs = await googleAccounts();
    for (final a in accs) {
      await clearGoogleFor(a);
    }
    await _storage.delete(key: _kAccounts);
  }
}

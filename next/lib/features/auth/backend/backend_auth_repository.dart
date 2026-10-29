/// A logged-in session against our own backend. Nothing here overlaps
/// with [GoogleAuthAccount] on purpose — the two auth systems are kept
/// fully independent so the backend never has any Google token to leak,
/// mishandle, or accidentally log (see the CASA-avoidance architecture
/// from the design discussion: the backend must never touch Google data).
class BackendSession {
  const BackendSession({
    required this.userId,
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
  });

  final String userId;
  final String email;
  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiresAt;

  bool get isAccessTokenExpired => DateTime.now().isAfter(accessTokenExpiresAt);

  BackendSession copyWithAccessToken({
    required String accessToken,
    required DateTime expiresAt,
  }) {
    return BackendSession(
      userId: userId,
      email: email,
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessTokenExpiresAt: expiresAt,
    );
  }
}

class BackendAuthException implements Exception {
  const BackendAuthException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'BackendAuthException($statusCode): $message';
}

/// Contract for our own backend's auth (email/password, not Google OAuth
/// — see the earlier design discussion on why these stay separate).
///
/// Expected REST contract (backend doesn't exist yet as of Step 1 — this
/// is the shape it needs to implement):
///   POST /auth/register  {email, password} -> 201 {userId, email, accessToken, refreshToken, expiresIn}
///   POST /auth/login     {email, password} -> 200 {userId, email, accessToken, refreshToken, expiresIn}
///   POST /auth/refresh   {refreshToken}     -> 200 {accessToken, expiresIn}
///   POST /auth/logout    {refreshToken}     -> 204 (best-effort server-side invalidation)
abstract class BackendAuthRepository {
  /// Reads any persisted session from secure storage. Call once at
  /// startup, before trusting [currentSession].
  Future<void> restoreSession();

  Stream<BackendSession?> get sessionChanges;

  BackendSession? get currentSession;

  Future<void> register({required String email, required String password});

  Future<void> login({required String email, required String password});

  Future<void> logout();

  /// Returns a valid (non-expired) access token, transparently using the
  /// refresh token to mint a new one if the current one has expired.
  /// Unlike the Google side, this CAN be silent/automatic, since we
  /// control both ends of this token exchange.
  Future<String> getValidAccessToken();
}

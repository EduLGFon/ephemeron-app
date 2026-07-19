import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/dev_logger.dart';
import 'google_auth_repository.dart';

/// Implements [GoogleAuthRepository] on top of google_sign_in ^7.x.
///
/// Worth knowing if you've used this package before v7: the API changed
/// significantly (singleton instance, explicit initialize(), separate
/// authenticate()/authorizationClient calls instead of one signIn()
/// method). This class is written against the current API — see
/// https://pub.dev/packages/google_sign_in for the canonical reference if
/// something here looks unfamiliar.
// `extends`, not `implements` — GoogleAuthRepository provides a concrete
// default body for getCalendarAccessToken(); `implements` would treat it
// as a pure interface and require re-implementing that method here too.
// Found during real-device testing (surfaced as a missing-implementation
// compile error).
class GoogleSignInAuthRepository extends GoogleAuthRepository {
  GoogleSignInAuthRepository() : _instance = GoogleSignIn.instance;

  final GoogleSignIn _instance;
  final _accountController = StreamController<GoogleAuthAccount?>.broadcast();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _eventSubscription;
  // v7 removed GoogleSignIn.currentUser — the SDK no longer tracks "who's
  // signed in" for you, so this class does, from the authentication
  // events stream. _signedInAccount is the raw SDK object (needed for
  // .authorizationClient); _currentAccount is our stripped-down app model.
  GoogleSignInAccount? _signedInAccount;
  GoogleAuthAccount? _currentAccount;
  static bool _gsiInitialized = false;
  bool _initialized = false;

  @override
  Stream<GoogleAuthAccount?> get accountChanges => _accountController.stream;

  @override
  GoogleAuthAccount? get currentAccount => _currentAccount;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    // Restore persisted account identity from SharedPreferences immediately
    // so currentAccount is available at startup without waiting for network.
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('google.accountId');
    final savedEmail = prefs.getString('google.accountEmail');
    final savedName = prefs.getString('google.accountName');
    final savedPhoto = prefs.getString('google.accountPhoto');

    if (savedId != null && savedEmail != null) {
      _currentAccount = GoogleAuthAccount(
        id: savedId,
        email: savedEmail,
        displayName: savedName,
        photoUrl: savedPhoto,
      );
      _accountController.add(_currentAccount);
    }

    if (!_gsiInitialized) {
      DevLogger.log('Initializing GoogleSignIn (kIsWeb: $kIsWeb)');
      try {
        await _instance.initialize(
          clientId: kIsWeb ? AppConfig.googleWebClientId : null,
          serverClientId: kIsWeb ? null : AppConfig.googleWebClientId,
        );
        DevLogger.log('GoogleSignIn initialized successfully.');
        _gsiInitialized = true;
      } catch (e, stack) {
        DevLogger.logError('GoogleSignIn initialization failed', e, stack);
        rethrow;
      }
    } else {
      DevLogger.log('GoogleSignIn already initialized globally.');
    }

    _eventSubscription = _instance.authenticationEvents.listen(
      (event) {
        DevLogger.log('GoogleSignIn Auth Event: $event');
        _handleAuthEvent(event);
      },
      onError: (Object error, StackTrace stack) {
        // Stream errors come from failed authenticate() calls, not from
        // explicit sign-out events — don't treat them as sign-out.
        DevLogger.logError('GoogleSignIn event stream error', error, stack);
      },
    );

    _initialized = true;
  }

  void _handleAuthEvent(GoogleSignInAuthenticationEvent event) {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        _signedInAccount = event.user;
        final newAccount = _toAppAccount(event.user);
        if (_currentAccount != newAccount) {
          _currentAccount = newAccount;
          _persistAccount(_currentAccount);
          _accountController.add(_currentAccount);
        }
      case GoogleSignInAuthenticationEventSignOut():
        // The native SDK emits SignOut on startup if attemptLightweightAuthentication
        // doesn't yield an active credential. We only clear the SDK account reference.
        // We do NOT clear our persisted _currentAccount here, otherwise app restart wipes the session.
        // Explicit user sign out is handled by the signOut() method.
        _signedInAccount = null;
        break;
    }
  }

  Future<void> _persistAccount(GoogleAuthAccount? account) async {
    final prefs = await SharedPreferences.getInstance();
    if (account != null) {
      await prefs.setString('google.accountId', account.id);
      await prefs.setString('google.accountEmail', account.email);
      if (account.displayName != null) {
        await prefs.setString('google.accountName', account.displayName!);
      } else {
        await prefs.remove('google.accountName');
      }
      if (account.photoUrl != null) {
        await prefs.setString('google.accountPhoto', account.photoUrl!);
      } else {
        await prefs.remove('google.accountPhoto');
      }
    } else {
      await prefs.remove('google.accountId');
      await prefs.remove('google.accountEmail');
      await prefs.remove('google.accountName');
      await prefs.remove('google.accountPhoto');
    }
  }

  GoogleAuthAccount _toAppAccount(GoogleSignInAccount account) {
    return GoogleAuthAccount(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
    );
  }

  @override
  Future<void> signIn() async {
    _ensureInitialized();
    DevLogger.log('Starting Google Sign-In authenticate flow...');
    try {
      final account = await _instance.authenticate(
        scopeHint: const [
          AppConfig.googleCalendarScope,
          AppConfig.googleTasksScope,
        ],
      );
      _signedInAccount = account;
      _currentAccount = _toAppAccount(account);
      await _persistAccount(_currentAccount);
      _accountController.add(_currentAccount);
      DevLogger.log('Google Sign-In authenticate flow call completed.');
    } on GoogleSignInException catch (e, stack) {
      DevLogger.logError('Google Sign-In failed (GoogleSignInException)', e, stack);
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const GoogleAuthCancelledException();
      }
      throw GoogleAuthException(e.description ?? e.code.name);
    } catch (e, stack) {
      DevLogger.logError('Google Sign-In failed (generic error)', e, stack);
      throw GoogleAuthException(e.toString());
    }
  }

  @override
  Future<void> signOut() async {
    _ensureInitialized();
    try {
      await _instance.signOut();
    } catch (_) {}
    _signedInAccount = null;
    _currentAccount = null;
    await _persistAccount(null);
    _accountController.add(null);
  }

  @override
  Future<String> getAccessToken(
    List<String> scopes, {
    bool promptIfNecessary = false,
  }) async {
    _ensureInitialized();
    var signedInAccount = _signedInAccount;

    if (signedInAccount == null) {
      // If we don't have a signed in SDK account but we DO have a persisted
      // account, we can request authorization tokens silently by passing the
      // email directly to the platform interface. This avoids calling
      // attemptLightweightAuthentication() which triggers the One Tap UI
      // bottom sheet on Android even for silent requests.
      if (_currentAccount != null) {
        DevLogger.log('No active SDK session. Requesting token via platform interface for ${_currentAccount!.email}');
        try {
          final tokens = await GoogleSignInPlatform.instance.clientAuthorizationTokensForScopes(
            ClientAuthorizationTokensForScopesParameters(
              request: AuthorizationRequestDetails(
                scopes: scopes,
                userId: _currentAccount!.id,
                email: _currentAccount!.email,
                promptIfUnauthorized: promptIfNecessary,
              ),
            ),
          );
          if (tokens != null) {
            return tokens.accessToken;
          }
        } catch (e) {
          DevLogger.log('Silent token request via platform interface failed: $e');
        }

        if (!promptIfNecessary) {
          DevLogger.log('No cached token for scopes and promptIfNecessary is false.');
          throw const GoogleAuthException('Scope authorization token not available silently.');
        }

        DevLogger.log('Consent screen required. Triggering full signIn...');
        await signIn();
        signedInAccount = _signedInAccount;
        if (signedInAccount == null) {
          throw const GoogleAuthException('Failed to restore SDK session for authorization prompt.');
        }
      } else {
        DevLogger.logError('getAccessToken failed: No account signed in');
        throw const GoogleAuthException('No Google account signed in yet.');
      }
    }

    DevLogger.log('Requesting access token for scopes: $scopes');
    try {
      final existing = await signedInAccount.authorizationClient
          .authorizationForScopes(scopes);
      if (existing != null) {
        DevLogger.log('Found existing authorized access token.');
        return existing.accessToken;
      }

      if (!promptIfNecessary) {
        DevLogger.log('No cached token for scopes and promptIfNecessary is false.');
        throw const GoogleAuthException('Scope authorization token not available silently.');
      }

      DevLogger.log('Consent screen required. Triggering authorizeScopes...');
      final authorized =
          await signedInAccount.authorizationClient.authorizeScopes(scopes);
      DevLogger.log('authorizeScopes succeeded.');
      return authorized.accessToken;
    } on GoogleSignInException catch (e, stack) {
      DevLogger.logError('getAccessToken failed (GoogleSignInException)', e, stack);
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const GoogleAuthCancelledException();
      }
      throw GoogleAuthException(e.description ?? e.code.name);
    } catch (e, stack) {
      DevLogger.logError('getAccessToken failed (generic error)', e, stack);
      throw GoogleAuthException(e.toString());
    }
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'GoogleSignInAuthRepository.initialize() must be called and '
        'awaited before use.',
      );
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _accountController.close();
  }
}

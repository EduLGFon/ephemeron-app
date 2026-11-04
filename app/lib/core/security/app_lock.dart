// Optional biometric app lock (PLAN 8.4). UI gate only: when enabled in
// settings, the app shows a lock screen until the user authenticates.
// Unsupported devices degrade gracefully (no lock).
import 'package:local_auth/local_auth.dart';

class AppLock {
  /// Whether this device can actually authenticate the user. Unsupported
  /// platforms (and any platform where the plugin is unavailable) report
  /// false so callers can disable the feature instead of getting stuck.
  static Future<bool> isSupported() async {
    final auth = LocalAuthentication();
    try {
      return await auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Alias kept for callers/tests that use a different name.
  static Future<bool> isAvailable() => isSupported();

  /// Returns true on success. Returns false when the user cancels.
  /// Throws [LocalAuthException] for other failures so the UI can show
  /// a reason instead of leaving a dead Unlock button.
  /// SECURITY: fail closed, callers must stay locked on throw or false.
  static Future<bool> authenticate() async {
    // Devices without biometric/device-credential support cannot lock the
    // app; pass through instead of failing closed.
    if (!await isSupported()) return true;
    final auth = LocalAuthentication();
    try {
      return await auth.authenticate(
        localizedReason: 'Unlock Ephemeron',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      // User dismissal is not an error, stay locked quietly.
      if (e.code == LocalAuthExceptionCode.userCanceled ||
          e.code == LocalAuthExceptionCode.systemCanceled) {
        return false;
      }
      rethrow;
    }
  }

  /// User-visible reason for an authentication failure.
  static String describeError(Object e) {
    if (e is LocalAuthException) {
      switch (e.code) {
        case LocalAuthExceptionCode.noBiometricsEnrolled:
        case LocalAuthExceptionCode.noCredentialsSet:
          return 'No screen lock enrolled. Add a PIN or biometric in system settings.';
        case LocalAuthExceptionCode.noBiometricHardware:
          return 'This device has no biometric hardware.';
        case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
          return 'Biometric hardware is temporarily unavailable. Try again.';
        case LocalAuthExceptionCode.temporaryLockout:
        case LocalAuthExceptionCode.biometricLockout:
          return 'Too many attempts. Use your device PIN to unlock.';
        case LocalAuthExceptionCode.uiUnavailable:
          return 'System unlock UI is unavailable. Update the app and try again.';
        case LocalAuthExceptionCode.authInProgress:
          return 'An unlock is already in progress.';
        case LocalAuthExceptionCode.timeout:
          return 'Unlock timed out. Try again.';
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
          return 'Unlock was cancelled.';
        case LocalAuthExceptionCode.userRequestedFallback:
        case LocalAuthExceptionCode.deviceError:
        case LocalAuthExceptionCode.unknownError:
          return 'Unlock failed. Try again.';
      }
    }
    return 'Unlock failed. Try again.';
  }
}

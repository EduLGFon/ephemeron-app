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

  static Future<bool> authenticate() async {
    // Devices without biometric/device-credential support cannot lock the
    // app; pass through instead of failing closed.
    if (!await isSupported()) return true;
    final auth = LocalAuthentication();
    try {
      return await auth.authenticate(
        localizedReason: 'Unlock Ephemeron',
        biometricOnly: false,
      );
    } catch (_) {
      return false;
    }
  }
}

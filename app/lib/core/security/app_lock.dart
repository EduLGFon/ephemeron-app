// Optional biometric app lock (PLAN 8.4). UI gate only: when enabled in
// settings, the app shows a lock screen until the user authenticates.
// Unsupported devices degrade gracefully (no lock).
import 'package:local_auth/local_auth.dart';

class AppLock {
  static Future<bool> authenticate() async {
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) return true;
      return await auth.authenticate(
        localizedReason: 'Unlock Ephemeron',
        biometricOnly: false,
      );
    } catch (_) {
      return false;
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

import 'package:ephemeron/core/security/app_lock.dart';

void main() {
  test('describeError maps lockout to PIN fallback message', () {
    expect(
      AppLock.describeError(
        const LocalAuthException(code: LocalAuthExceptionCode.biometricLockout),
      ),
      contains('PIN'),
    );
    expect(
      AppLock.describeError(
        const LocalAuthException(code: LocalAuthExceptionCode.temporaryLockout),
      ),
      contains('PIN'),
    );
  });

  test('describeError maps missing enrollment to setup message', () {
    expect(
      AppLock.describeError(
        const LocalAuthException(
          code: LocalAuthExceptionCode.noBiometricsEnrolled,
        ),
      ),
      contains('No screen lock'),
    );
    expect(
      AppLock.describeError(
        const LocalAuthException(code: LocalAuthExceptionCode.noCredentialsSet),
      ),
      contains('No screen lock'),
    );
  });

  test('describeError maps unavailable UI instead of empty failure', () {
    expect(
      AppLock.describeError(
        const LocalAuthException(code: LocalAuthExceptionCode.uiUnavailable),
      ),
      isNot('Unlock failed. Try again.'),
    );
  });
}

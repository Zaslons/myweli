import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';

/// The permanent guard behind the DI flip
/// (docs/design/push-notifications-app.md).
///
/// The real `FcmPushNotificationService` is wired ONLY when
/// `AppConfig.useApiBackend` is on. No test sets `USE_API_BACKEND`, so every
/// `flutter test` run must keep the mock — otherwise the four suites that call
/// `setupDependencyInjection()` would reach `FirebaseMessaging.instance` with
/// no native app and die.
///
/// If someone ever ungates that line, this test is what tells them.
void main() {
  test('under `flutter test`, the push seam is always the MOCK', () {
    setupDependencyInjection();
    expect(
      serviceLocator.pushNotificationService,
      isA<MockPushNotificationService>(),
      reason: 'the real FCM adapter must never be constructed in tests — it '
          'needs a native Firebase app (see the file header)',
    );
  });
}

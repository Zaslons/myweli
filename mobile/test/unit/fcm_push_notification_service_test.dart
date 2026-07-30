import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/services/interfaces/push_notification_service_interface.dart';
import 'package:myweli/services/push/fcm_push_notification_service.dart';

/// The FCM adapter's PURE part. The class itself is never constructed here —
/// its methods reach `FirebaseMessaging.instance` → `Firebase.app()`, which
/// throws without a native app. Importing the file is safe (the mapping
/// function is plain Dart); DI only builds the class when
/// `AppConfig.useApiBackend` is on, which no test sets.
void main() {
  group('mapAuthorizationStatus', () {
    test('authorized → granted', () {
      expect(
        mapAuthorizationStatus(AuthorizationStatus.authorized),
        PushPermissionStatus.granted,
      );
    });

    test(
        'provisional → granted (iOS quiet notifications still ARRIVE, so the '
        'token is worth registering)', () {
      expect(
        mapAuthorizationStatus(AuthorizationStatus.provisional),
        PushPermissionStatus.granted,
      );
    });

    test('denied → denied (the prefs screen offers the re-enable path)', () {
      expect(
        mapAuthorizationStatus(AuthorizationStatus.denied),
        PushPermissionStatus.denied,
      );
    });

    test('notDetermined → notDetermined (the one state that may prompt)', () {
      expect(
        mapAuthorizationStatus(AuthorizationStatus.notDetermined),
        PushPermissionStatus.notDetermined,
      );
    });
  });
}

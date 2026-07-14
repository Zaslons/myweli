import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/logger.dart';
import '../interfaces/push_notification_service_interface.dart';

/// The REAL push seam: `firebase_messaging` behind
/// [PushNotificationServiceInterface] (docs/design/push-notifications-app.md).
///
/// Two invariants keep this safe, and both are load-bearing:
///
/// 1. **Lazy.** Nothing touches Firebase in the constructor — [_fcm] is a
///    getter, never a field. `PushRegistration`'s constructor subscribes to
///    [onTokenRefresh] from inside `ServiceLocator.setup()`, so an eager
///    `FirebaseMessaging.instance` would blow up app boot (and every test that
///    calls `setupDependencyInjection()`) whenever Firebase isn't initialized.
/// 2. **It degrades, it never throws.** Missing/broken platform config, no
///    APNs token on iOS, Firebase not initialized → `notDetermined` / `null` /
///    an empty stream. `PushRegistration` then simply no-ops: it never
///    registers a device it couldn't get a real token for.
///
/// NO TEST MAY CONSTRUCT THIS CLASS — its methods reach
/// `FirebaseMessaging.instance` → `Firebase.app()`, which throws without a
/// native app. Importing the file for [mapAuthorizationStatus] is fine (that
/// function is pure); DI only builds it when `AppConfig.useApiBackend` is on,
/// which no test sets.
class FcmPushNotificationService implements PushNotificationServiceInterface {
  FcmPushNotificationService();

  FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  @override
  Future<PushPermissionStatus> permissionStatus() async {
    try {
      final settings = await _fcm.getNotificationSettings();
      return mapAuthorizationStatus(settings.authorizationStatus);
    } catch (e, s) {
      AppLogger.error('Push: permissionStatus failed', error: e, stackTrace: s);
      return PushPermissionStatus.notDetermined;
    }
  }

  @override
  Future<PushPermissionStatus> requestPermission() async {
    try {
      // Android 13+: this is what raises the POST_NOTIFICATIONS dialog.
      final settings = await _fcm.requestPermission();
      return mapAuthorizationStatus(settings.authorizationStatus);
    } catch (e, s) {
      AppLogger.error(
        'Push: requestPermission failed',
        error: e,
        stackTrace: s,
      );
      return PushPermissionStatus.notDetermined;
    }
  }

  @override
  Future<String?> getToken() async {
    try {
      // iOS hands out an FCM token only once APNs has registered the device;
      // without an APNs key (or on a simulator) it stays null — that's a
      // no-op registration, not an error.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final apns = await _fcm.getAPNSToken();
        if (apns == null) return null;
      }
      return await _fcm.getToken();
    } catch (e, s) {
      AppLogger.error('Push: getToken failed', error: e, stackTrace: s);
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh {
    try {
      return _fcm.onTokenRefresh;
    } catch (e, s) {
      AppLogger.error('Push: onTokenRefresh unavailable',
          error: e, stackTrace: s);
      return const Stream<String>.empty();
    }
  }
}

/// FCM's permission enum → ours. Pure; the only part of this file a test may
/// touch.
///
/// `provisional` (iOS quiet notifications) counts as GRANTED: the device does
/// receive pushes, they just land silently in the notification centre — so we
/// register the token.
@visibleForTesting
PushPermissionStatus mapAuthorizationStatus(AuthorizationStatus status) {
  switch (status) {
    case AuthorizationStatus.authorized:
    case AuthorizationStatus.provisional:
      return PushPermissionStatus.granted;
    case AuthorizationStatus.denied:
      return PushPermissionStatus.denied;
    case AuthorizationStatus.notDetermined:
      return PushPermissionStatus.notDetermined;
  }
}

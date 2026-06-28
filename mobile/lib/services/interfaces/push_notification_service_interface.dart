/// Device-level push (FCM) capability: OS permission + the device token.
///
/// This is the seam between the app and Firebase Cloud Messaging. The default
/// DI wiring is [MockPushNotificationService]; the real `FcmPushNotificationService`
/// (firebase_messaging) lands in the accounts phase — swapping it in is a single
/// DI line. Design: docs/design/push-notifications-app.md.
abstract class PushNotificationServiceInterface {
  /// The current OS notification-permission status (no prompt).
  Future<PushPermissionStatus> permissionStatus();

  /// Shows the OS permission prompt (if undetermined) and returns the result.
  Future<PushPermissionStatus> requestPermission();

  /// The current device token, or null if unavailable / permission not granted.
  Future<String?> getToken();

  /// Emits a new token whenever FCM rotates it, so callers can re-register.
  Stream<String> get onTokenRefresh;
}

/// OS-level notification permission state.
enum PushPermissionStatus { notDetermined, granted, denied }

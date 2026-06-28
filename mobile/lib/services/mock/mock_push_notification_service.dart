import 'dart:async';

import '../interfaces/push_notification_service_interface.dart';

/// In-memory mock of [PushNotificationServiceInterface] (the DI default until the
/// real FCM plugin lands in the accounts phase). Starts undetermined; the first
/// [requestPermission] grants. Simulates latency. Design:
/// docs/design/push-notifications-app.md.
class MockPushNotificationService implements PushNotificationServiceInterface {
  MockPushNotificationService({
    PushPermissionStatus initial = PushPermissionStatus.notDetermined,
    String token = 'mock-fcm-token',
  })  : _status = initial,
        _token = token;

  PushPermissionStatus _status;
  final String _token;
  final StreamController<String> _refresh =
      StreamController<String>.broadcast();

  @override
  Future<PushPermissionStatus> permissionStatus() async {
    await _delay();
    return _status;
  }

  @override
  Future<PushPermissionStatus> requestPermission() async {
    await _delay();
    if (_status == PushPermissionStatus.notDetermined) {
      _status = PushPermissionStatus.granted;
    }
    return _status;
  }

  @override
  Future<String?> getToken() async {
    await _delay();
    return _status == PushPermissionStatus.granted ? _token : null;
  }

  @override
  Stream<String> get onTokenRefresh => _refresh.stream;

  // ---- test helpers (simulate denial / rotation) ----
  void setStatus(PushPermissionStatus status) => _status = status;
  void emitRefresh(String token) => _refresh.add(token);

  Future<void> _delay() => Future<void>.delayed(
        const Duration(milliseconds: 50),
      );
}

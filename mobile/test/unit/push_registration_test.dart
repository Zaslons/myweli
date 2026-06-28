import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/services/interfaces/push_notification_service_interface.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('registerIfGranted registers only when permission is granted', () async {
    final granted = MockDeviceRegistrationService();
    await PushRegistration(
      push: MockPushNotificationService(initial: PushPermissionStatus.granted),
      devices: granted,
    ).registerIfGranted();
    expect(granted.registeredTokens, contains('mock-fcm-token'));

    final undetermined = MockDeviceRegistrationService();
    await PushRegistration(
      push: MockPushNotificationService(),
      devices: undetermined,
    ).registerIfGranted();
    expect(undetermined.registeredTokens, isEmpty);
  });

  test('after first booking: accept → prompt, grant, register; asked once',
      () async {
    final devices = MockDeviceRegistrationService();
    final coord = PushRegistration(
      push: MockPushNotificationService(),
      devices: devices,
    );
    var prompts = 0;
    await coord.maybePromptAfterFirstBooking(() async {
      prompts++;
      return true;
    });
    expect(prompts, 1);
    expect(devices.registeredTokens, contains('mock-fcm-token'));

    // A second booking must not prompt again.
    await coord.maybePromptAfterFirstBooking(() async {
      prompts++;
      return true;
    });
    expect(prompts, 1);
  });

  test('after first booking: decline → asked set, not registered (no nag)',
      () async {
    final devices = MockDeviceRegistrationService();
    final coord = PushRegistration(
      push: MockPushNotificationService(),
      devices: devices,
    );
    var prompts = 0;
    await coord.maybePromptAfterFirstBooking(() async {
      prompts++;
      return false;
    });
    expect(prompts, 1);
    expect(devices.registeredTokens, isEmpty);

    await coord.maybePromptAfterFirstBooking(() async {
      prompts++;
      return false;
    });
    expect(prompts, 1); // not asked again
  });

  test('already granted → registers without showing the rationale', () async {
    final devices = MockDeviceRegistrationService();
    var prompts = 0;
    await PushRegistration(
      push: MockPushNotificationService(initial: PushPermissionStatus.granted),
      devices: devices,
    ).maybePromptAfterFirstBooking(() async {
      prompts++;
      return true;
    });
    expect(prompts, 0);
    expect(devices.registeredTokens, contains('mock-fcm-token'));
  });

  test('denied → no prompt, no register', () async {
    final devices = MockDeviceRegistrationService();
    var prompts = 0;
    await PushRegistration(
      push: MockPushNotificationService(initial: PushPermissionStatus.denied),
      devices: devices,
    ).maybePromptAfterFirstBooking(() async {
      prompts++;
      return true;
    });
    expect(prompts, 0);
    expect(devices.registeredTokens, isEmpty);
  });

  test('unregister removes the token', () async {
    final devices = MockDeviceRegistrationService();
    final coord = PushRegistration(
      push: MockPushNotificationService(initial: PushPermissionStatus.granted),
      devices: devices,
    );
    await coord.registerIfGranted();
    expect(devices.registeredTokens, isNotEmpty);
    await coord.unregister();
    expect(devices.registeredTokens, isEmpty);
  });

  test('token refresh re-registers when granted', () async {
    final devices = MockDeviceRegistrationService();
    final push =
        MockPushNotificationService(initial: PushPermissionStatus.granted);
    PushRegistration(push: push, devices: devices);
    push.emitRefresh('rotated-token');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(devices.registeredTokens, contains('rotated-token'));
  });
}

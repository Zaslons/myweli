import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/push/push_offer.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/services/interfaces/push_notification_service_interface.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// consumer-signin-push.md §2.9–§2.10, decisions 209–210: « Plus tard »
/// means later — up to three offers, at least 7 days apart, every offer
/// counted — and Préférences can ask at any time.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pushOfferDecision', () {
    final now = DateTime.utc(2026, 11, 24, 12);
    PushOfferAction decide(
      PushPermissionStatus status, {
      int count = 0,
      DateTime? last,
    }) => pushOfferDecision(
      status: status,
      offerCount: count,
      lastOfferAt: last,
      now: now,
    );

    test('granted registers, whatever was offered', () {
      for (final count in [0, 1, 2, 3, 9]) {
        expect(
          decide(PushPermissionStatus.granted, count: count, last: now),
          PushOfferAction.register,
        );
      }
    });

    test('denied does nothing: Préférences shows the way', () {
      for (final count in [0, 1, 3]) {
        expect(
          decide(PushPermissionStatus.denied, count: count),
          PushOfferAction.none,
        );
      }
    });

    test(
      'not determined: offered while fewer than 3, at least 7 days apart',
      () {
        const nd = PushPermissionStatus.notDetermined;
        expect(decide(nd), PushOfferAction.offer);
        expect(decide(nd, count: 1), PushOfferAction.offer); // the old flag
        expect(
          decide(nd, count: 1, last: now.subtract(const Duration(days: 7))),
          PushOfferAction.offer,
          reason: 'the boundary: exactly 7 days is enough',
        );
        expect(
          decide(
            nd,
            count: 1,
            last: now.subtract(const Duration(days: 6, hours: 23)),
          ),
          PushOfferAction.none,
          reason: 'one hour short of 7 days',
        );
        expect(
          decide(nd, count: 2, last: now.subtract(const Duration(days: 30))),
          PushOfferAction.offer,
          reason: 'the third offer',
        );
        expect(
          decide(nd, count: 3, last: now.subtract(const Duration(days: 365))),
          PushOfferAction.none,
          reason: 'after the third, only Préférences',
        );
      },
    );

    test('the limits are the decided numbers', () {
      expect(kPushOfferMax, 3);
      expect(kPushOfferGap, const Duration(days: 7));
    });
  });

  group('maybeOfferAfterBooking', () {
    late void Function() unfreeze;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      unfreeze = AppClock.freeze(DateTime.utc(2026, 11, 24, 12));
    });
    tearDown(() => unfreeze());

    PushRegistration coord(
      MockPushNotificationService push,
      MockDeviceRegistrationService devices,
    ) => PushRegistration(push: push, devices: devices);

    test('« Plus tard » no longer ends it: offered again 7 days later, three '
        'times in all', () async {
      final push = MockPushNotificationService();
      final devices = MockDeviceRegistrationService();
      final c = coord(push, devices);
      var offers = 0;
      Future<bool> later() async {
        offers++;
        return false;
      }

      await c.maybeOfferAfterBooking(later);
      expect(offers, 1);
      await c.maybeOfferAfterBooking(later); // same day: no
      expect(offers, 1);

      unfreeze();
      unfreeze = AppClock.freeze(DateTime.utc(2026, 12, 1, 12)); // +7 days
      await c.maybeOfferAfterBooking(later);
      expect(offers, 2);

      unfreeze();
      unfreeze = AppClock.freeze(DateTime.utc(2026, 12, 8, 12));
      await c.maybeOfferAfterBooking(later);
      expect(offers, 3);

      unfreeze();
      unfreeze = AppClock.freeze(DateTime.utc(2027, 6, 1, 12));
      await c.maybeOfferAfterBooking(later);
      expect(offers, 3, reason: 'never a fourth');
      expect(devices.registeredTokens, isEmpty);
      expect(await push.permissionStatus(), PushPermissionStatus.notDetermined);
    });

    test('a failed « Activer » counts too — no unlimited sheet', () async {
      final push = _FailingRequest();
      final devices = MockDeviceRegistrationService();
      final c = coord(push, devices);
      var offers = 0;
      await c.maybeOfferAfterBooking(() async {
        offers++;
        return true;
      });
      expect(offers, 1);
      expect(await push.permissionStatus(), PushPermissionStatus.notDetermined);
      await c.maybeOfferAfterBooking(() async {
        offers++;
        return true;
      });
      expect(offers, 1, reason: 'counted, so not again the same day');
    });

    test('« Activer » → the system prompt, granted → registered', () async {
      final devices = MockDeviceRegistrationService();
      await coord(
        MockPushNotificationService(),
        devices,
      ).maybeOfferAfterBooking(() async => true);
      expect(devices.registeredTokens, contains('mock-fcm-token'));
    });

    test('granted: registered silently, no sheet', () async {
      final devices = MockDeviceRegistrationService();
      var offers = 0;
      await coord(
        MockPushNotificationService(initial: PushPermissionStatus.granted),
        devices,
      ).maybeOfferAfterBooking(() async {
        offers++;
        return true;
      });
      expect(offers, 0);
      expect(devices.registeredTokens, contains('mock-fcm-token'));
    });

    test('denied: no sheet', () async {
      var offers = 0;
      await coord(
        MockPushNotificationService(initial: PushPermissionStatus.denied),
        MockDeviceRegistrationService(),
      ).maybeOfferAfterBooking(() async {
        offers++;
        return true;
      });
      expect(offers, 0);
    });
  });

  group('the old ask-once flag', () {
    late void Function() unfreeze;
    setUp(() => unfreeze = AppClock.freeze(DateTime.utc(2026, 11, 24, 12)));
    tearDown(() => unfreeze());

    test('set, still « not determined »: one offer with no date — offered '
        'after the next booking — and the key goes', () async {
      SharedPreferences.setMockInitialValues({'myweli_push_asked': true});
      var offers = 0;
      await PushRegistration(
        push: MockPushNotificationService(),
        devices: MockDeviceRegistrationService(),
      ).maybeOfferAfterBooking(() async {
        offers++;
        return false;
      });
      expect(offers, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('myweli_push_asked'), isFalse);
      expect(prefs.getInt('myweli_push_offer_count'), 2);
    });

    test(
      'set while granted or denied: nothing more than the key going',
      () async {
        for (final status in [
          PushPermissionStatus.granted,
          PushPermissionStatus.denied,
        ]) {
          SharedPreferences.setMockInitialValues({'myweli_push_asked': true});
          await PushRegistration(
            push: MockPushNotificationService(initial: status),
            devices: MockDeviceRegistrationService(),
          ).maybeOfferAfterBooking(() async => false);
          final prefs = await SharedPreferences.getInstance();
          expect(
            prefs.containsKey('myweli_push_asked'),
            isFalse,
            reason: '$status',
          );
          expect(prefs.containsKey('myweli_push_offer_count'), isFalse);
        }
      },
    );
  });

  group('enableFromSettings (Préférences)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('granted → registered, and answered', () async {
      final devices = MockDeviceRegistrationService();
      final status = await PushRegistration(
        push: MockPushNotificationService(),
        devices: devices,
      ).enableFromSettings();
      expect(status, PushPermissionStatus.granted);
      expect(devices.registeredTokens, contains('mock-fcm-token'));
    });

    test(
      'a failure answers « not determined » and registers nothing',
      () async {
        final devices = MockDeviceRegistrationService();
        final status = await PushRegistration(
          push: _FailingRequest(),
          devices: devices,
        ).enableFromSettings();
        expect(status, PushPermissionStatus.notDetermined);
        expect(devices.registeredTokens, isEmpty);
      },
    );
  });

  group('a sign-out right after a sign-in (the phone step\'s « Fermer », '
      '§2.2)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a registration not yet SENT is dropped — the signed-out phone is '
        'left registered to no account', () async {
      final devices = _Log();
      final c = PushRegistration(
        push: MockPushNotificationService(
          initial: PushPermissionStatus.granted,
        ),
        devices: devices,
      );
      final reg = c.registerIfGranted(); // not awaited, as at sign-in
      final unreg = c.unregister();
      await Future.wait([reg, unreg]);
      expect(devices.log, ['unregister']);
      expect(devices.registeredTokens, isEmpty);
    });

    test('CONTROL — once it was sent, it stays, and the sign-out unregisters '
        'after it', () async {
      final devices = _Log();
      final c = PushRegistration(
        push: MockPushNotificationService(
          initial: PushPermissionStatus.granted,
        ),
        devices: devices,
      );
      await c.registerIfGranted();
      await c.unregister();
      expect(devices.log, ['register', 'unregister']);
      expect(devices.registeredTokens, isEmpty);
    });

    test('a sign-out never waits for a registration: it answers while one '
        'is still in flight', () async {
      final devices = _Log(hangRegister: true);
      final c = PushRegistration(
        push: MockPushNotificationService(
          initial: PushPermissionStatus.granted,
        ),
        devices: devices,
      );
      unawaited(c.registerIfGranted()); // sent, and never answers
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(devices.log, ['register…']);
      await c.unregister().timeout(const Duration(seconds: 1));
      expect(devices.log, ['register…', 'unregister']);
    });
  });
}

/// The adapter's answer when the plugin fails: « not determined », and the
/// system still says so afterwards.
class _FailingRequest extends MockPushNotificationService {
  @override
  Future<PushPermissionStatus> requestPermission() async =>
      PushPermissionStatus.notDetermined;
}

/// What reached the server, in order. [hangRegister]: a registration that is
/// sent and never answers.
class _Log extends MockDeviceRegistrationService {
  _Log({this.hangRegister = false});

  final bool hangRegister;
  final log = <String>[];

  @override
  Future<ApiResponse<bool>> register(String token, String platform) async {
    if (hangRegister) {
      log.add('register…');
      // Sent; its answer never comes.
      return Completer<ApiResponse<bool>>().future;
    }
    log.add('register');
    return super.register(token, platform);
  }

  @override
  Future<ApiResponse<bool>> unregister(String token) async {
    log.add('unregister');
    return super.unregister(token);
  }
}

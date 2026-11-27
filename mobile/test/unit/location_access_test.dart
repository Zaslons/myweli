import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myweli/core/location/location_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_location.dart';

/// The shared location flow (docs/design/consumer-location.md §5, §8.1).
///
/// Each answer the phone can give maps to one outcome; `status()` never asks
/// and never throws; one read at a time; the « explained » flag records the
/// person's tap and nothing else. Answered through geolocator's own channel,
/// as the plugin's Dart side reads it.
void main() {
  final access = LocationAccess.instance;
  late FakePhoneLocation phone;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    phone = FakePhoneLocation();
  });

  Future<bool> flag() async =>
      (await SharedPreferences.getInstance()).getBool(
        LocationAccess.explainedKey,
      ) ??
      false;

  /// [locate] on the fake clock: pumped until it answers.
  Future<LocationOutcome> run(
    WidgetTester tester, {
    LocationAccuracy accuracy = LocationAccuracy.medium,
    bool ask = true,
  }) async {
    LocationOutcome? outcome;
    unawaited(
      access.locate(accuracy: accuracy, ask: ask).then((o) => outcome = o),
    );
    for (var i = 0; i < 20 && outcome == null; i++) {
      await tester.pump();
    }
    expect(outcome, isNotNull, reason: 'locate() did not answer');
    return outcome!;
  }

  group('status(): what the phone allows, with no dialog', () {
    for (final (check, expected) in [
      (FakePhoneLocation.whileInUse, LocationStatus.allowed),
      (3, LocationStatus.allowed), // always
      (FakePhoneLocation.denied, LocationStatus.undecided),
      (FakePhoneLocation.deniedForever, LocationStatus.blocked),
    ]) {
      testWidgets('permission $check → $expected', (tester) async {
        phone
          ..check = check
          ..install(tester);
        expect(await access.status(), expected);
        expect(phone.count('requestPermission'), 0);
      });
    }

    testWidgets('location off → off, before the permission is read', (
      tester,
    ) async {
      phone
        ..service = false
        ..install(tester);
      expect(await access.status(), LocationStatus.off);
      expect(phone.calls, ['isLocationServiceEnabled']);
    });

    testWidgets('no plugin at all → unknown, no throw', (tester) async {
      // No mock: the engine answers « no implementation », on the real clock.
      final status = await tester.runAsync(access.status);
      expect(status, LocationStatus.unknown);
    });

    testWidgets('a null permission (the plugin throws on it) → unknown', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        FakePhoneLocation.channel,
        (call) async => call.method == 'isLocationServiceEnabled' ? true : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          FakePhoneLocation.channel,
          null,
        ),
      );
      expect(await access.status(), LocationStatus.unknown);
    });

    testWidgets('a plugin error → unknown', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        FakePhoneLocation.channel,
        (call) async => throw PlatformException(code: 'boom'),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          FakePhoneLocation.channel,
          null,
        ),
      );
      expect(await access.status(), LocationStatus.unknown);
    });

    testWidgets('never sets the explained flag', (tester) async {
      phone.install(tester);
      await access.status();
      expect(await flag(), isFalse);
    });
  });

  group('locate(): every answer to its outcome', () {
    testWidgets('allowed: the position, with no request', (tester) async {
      phone
        ..check = FakePhoneLocation.whileInUse
        ..install(tester);
      final outcome = await run(tester);
      expect(outcome, isA<Located>());
      final located = outcome as Located;
      expect(located.position.latitude, 5.30);
      expect(located.position.accuracy, 20);
      expect(located.approximate, isFalse);
      expect(phone.count('requestPermission'), 0);
    });

    testWidgets('undecided, then allowed in the dialog: the position', (
      tester,
    ) async {
      phone
        ..requests = [FakePhoneLocation.whileInUse]
        ..install(tester);
      expect(await run(tester), isA<Located>());
      expect(phone.count('requestPermission'), 1);
    });

    testWidgets('Android: refused in the dialog → refused, may ask again', (
      tester,
    ) async {
      phone
        ..requests = [FakePhoneLocation.denied]
        ..install(tester);
      expect(await run(tester), isA<LocationRefused>());
    });

    testWidgets('iOS: a denied that survives a request → restricted', (
      tester,
    ) async {
      phone
        ..requests = [FakePhoneLocation.denied]
        ..install(tester);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        expect(await run(tester), isA<LocationRestricted>());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('refused for good at the request → blocked', (tester) async {
      phone
        ..requests = [FakePhoneLocation.deniedForever]
        ..install(tester);
      expect(await run(tester), isA<LocationBlocked>());
    });

    testWidgets('refused for good already → blocked, no request', (
      tester,
    ) async {
      phone
        ..check = FakePhoneLocation.deniedForever
        ..install(tester);
      expect(await run(tester), isA<LocationBlocked>());
      expect(phone.count('requestPermission'), 0);
    });

    testWidgets('location off → off, no request', (tester) async {
      phone
        ..service = false
        ..install(tester);
      expect(await run(tester), isA<LocationOff>());
      expect(phone.count('requestPermission'), 0);
    });

    testWidgets('location turned off during the read → off', (tester) async {
      phone
        ..check = FakePhoneLocation.whileInUse
        ..positionError = 'LOCATION_SERVICES_DISABLED'
        ..install(tester);
      expect(await run(tester), isA<LocationOff>());
    });

    testWidgets('the plugin fails → failed', (tester) async {
      phone
        ..check = FakePhoneLocation.whileInUse
        ..positionError = 'LOCATION_UPDATE_FAILURE'
        ..install(tester);
      expect(await run(tester), isA<LocationFailed>());
    });

    testWidgets('approximate: the phone says reduced', (tester) async {
      phone
        ..check = FakePhoneLocation.whileInUse
        ..accuracyStatus = 0
        ..install(tester);
      expect((await run(tester) as Located).approximate, isTrue);
    });

    testWidgets('an unreadable accuracy is not called approximate', (
      tester,
    ) async {
      phone
        ..check = FakePhoneLocation.whileInUse
        ..accuracyStatus = null
        ..install(tester);
      expect((await run(tester) as Located).approximate, isFalse);
    });

    testWidgets('asks for the accuracy it is given', (tester) async {
      Map<Object?, Object?>? settings;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        FakePhoneLocation.channel,
        (call) async {
          if (call.method == 'getCurrentPosition') {
            settings = call.arguments as Map<Object?, Object?>?;
          }
          return switch (call.method) {
            'isLocationServiceEnabled' => true,
            'checkPermission' => FakePhoneLocation.whileInUse,
            'getCurrentPosition' => {
              'latitude': 5.3,
              'longitude': -4.0,
              'timestamp': 0,
            },
            _ => null,
          };
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          FakePhoneLocation.channel,
          null,
        ),
      );
      LocationAccess.instance.debugReset();
      await run(tester, accuracy: LocationAccuracy.medium);
      expect(settings?['accuracy'], LocationAccuracy.medium.index);
      // The 30 s limit lives on the plugin's Dart side, not in these
      // settings: the next test proves it bounds the read.
    });

    testWidgets('no position within 30 s → failed, and not before', (
      tester,
    ) async {
      phone
        ..check = FakePhoneLocation.whileInUse
        ..holdPosition = Completer<Object?>()
        ..install(tester);
      LocationOutcome? outcome;
      unawaited(
        access
            .locate(accuracy: LocationAccuracy.medium)
            .then((o) => outcome = o),
      );
      await tester.pump(const Duration(seconds: 29));
      expect(outcome, isNull, reason: 'gave up before the bound');
      await tester.pump(const Duration(seconds: 2));
      expect(outcome, isA<LocationFailed>());
    });

    testWidgets('ask: false never opens the dialog', (tester) async {
      phone.install(tester); // undecided
      expect(await run(tester, ask: false), isA<LocationRefused>());
      expect(phone.count('requestPermission'), 0);
      expect(await flag(), isFalse, reason: 'a silent read is not a tap');
    });
  });

  group('a permission request that never answers (review, 2026-11-27)', () {
    testWidgets('fails after 2 minutes, and the next tap asks again', (
      tester,
    ) async {
      // Android drops the callback when the result comes back empty
      // (`PermissionManager.java:148-153`).
      phone
        ..holdRequest = Completer<int>()
        ..install(tester);
      LocationOutcome? outcome;
      unawaited(
        access
            .locate(accuracy: LocationAccuracy.medium)
            .then((o) => outcome = o),
      );
      await tester.pump(const Duration(seconds: 119));
      expect(outcome, isNull, reason: 'the person may still be reading');
      await tester.pump(const Duration(seconds: 2));
      expect(outcome, isA<LocationFailed>());

      phone
        ..holdRequest = null
        ..requests = [FakePhoneLocation.whileInUse];
      expect(await run(tester), isA<Located>());
      expect(phone.count('requestPermission'), 2);
    });
  });

  group('recent(): the last position, with no dialog and no read', () {
    testWidgets('a position younger than 15 minutes', (tester) async {
      phone
        ..lastKnownAge = const Duration(minutes: 14)
        ..accuracyStatus = 0
        ..install(tester);
      final recent = await access.recent();
      expect(recent?.position.latitude, 5.30);
      expect(recent?.approximate, isTrue);
      expect(phone.count('getCurrentPosition'), 0);
      expect(phone.count('requestPermission'), 0);
    });

    for (final (label, age) in [
      ('older than 15 minutes', const Duration(minutes: 16)),
      ('none', null),
    ]) {
      testWidgets('$label → null', (tester) async {
        phone
          ..lastKnownAge = age
          ..install(tester);
        expect(await access.recent(), isNull);
      });
    }

    testWidgets('a plugin error → null, no throw', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        FakePhoneLocation.channel,
        (call) async => throw PlatformException(code: 'PERMISSION_DENIED'),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          FakePhoneLocation.channel,
          null,
        ),
      );
      expect(await access.recent(), isNull);
    });
  });

  group('the explained flag records the tap (§4)', () {
    testWidgets('set by locate(), even when it is refused', (tester) async {
      phone
        ..requests = [FakePhoneLocation.denied]
        ..install(tester);
      expect(await run(tester), isA<LocationRefused>());
      expect(await flag(), isTrue);
    });

    testWidgets('set by markExplained (« Plus tard »)', (tester) async {
      expect(await access.explained(), isFalse);
      await access.markExplained();
      expect(await access.explained(), isTrue);
    });
  });

  group('one read at a time, app-wide (§2.4)', () {
    testWidgets('two callers: one request, one read, one answer', (
      tester,
    ) async {
      phone
        ..holdRequest = Completer<int>()
        ..install(tester);
      final first = access.locate(accuracy: LocationAccuracy.medium);
      await tester.pump();
      final second = access.locate(accuracy: LocationAccuracy.medium);
      await tester.pump();
      phone.holdRequest!.complete(FakePhoneLocation.whileInUse);
      LocationOutcome? a;
      LocationOutcome? b;
      unawaited(first.then((o) => a = o));
      unawaited(second.then((o) => b = o));
      for (var i = 0; i < 20 && (a == null || b == null); i++) {
        await tester.pump();
      }
      expect(a, isA<Located>());
      expect(identical(a, b), isTrue, reason: 'the same read, shared');
      expect(phone.count('requestPermission'), 1);
      expect(phone.count('getCurrentPosition'), 1);
    });

    testWidgets('a call after the first ended reads again', (tester) async {
      phone
        ..check = FakePhoneLocation.whileInUse
        ..install(tester);
      await run(tester);
      await run(tester);
      expect(phone.count('getCurrentPosition'), 2);
    });
  });

  group('the Settings openers', () {
    testWidgets('each opens its own page', (tester) async {
      phone.install(tester);
      expect(await access.openAppSettings(), isTrue);
      expect(await access.openLocationSettings(), isTrue);
      expect(phone.calls, ['openAppSettings', 'openLocationSettings']);
    });

    testWidgets('a failure is false, never a throw', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        FakePhoneLocation.channel,
        (call) async => throw PlatformException(code: 'boom'),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          FakePhoneLocation.channel,
          null,
        ),
      );
      expect(await access.openAppSettings(), isFalse);
      expect(await access.openLocationSettings(), isFalse);
    });
  });
}

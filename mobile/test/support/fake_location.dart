import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/location/location_access.dart';
import 'package:myweli/core/utils/app_clock.dart';

/// A phone's location, as geolocator's method channel answers it
/// (`flutter.baseflow.com/geolocator`, the channel `GeolocatorPlatform`
/// reaches under `flutter test`). Scripted per test; every call recorded.
///
/// docs/design/consumer-location.md §8.1. The permission integers are the
/// plugin's own (`integer_extensions.dart`): 0 denied, 1 deniedForever,
/// 2 whileInUse, 3 always.
class FakePhoneLocation {
  static const channel = MethodChannel('flutter.baseflow.com/geolocator');

  static const denied = 0;
  static const deniedForever = 1;
  static const whileInUse = 2;

  /// The phone's location service.
  bool service = true;

  /// What `checkPermission` answers.
  int check = denied;

  /// What each `requestPermission` answers, in turn; the last repeats. Each
  /// answer becomes the next [check] as each platform reports it: on Android
  /// a refusal for good still checks as `denied` — `checkPermission` never
  /// says otherwise there (`PermissionManager.java:63-64`); on iOS it checks
  /// as `deniedForever`.
  List<int> requests = [deniedForever];

  /// How old the phone's last position is (`getLastKnownPosition`); `null`:
  /// it has none.
  Duration? lastKnownAge = const Duration(minutes: 1);

  /// Somewhere in Treichville, accurate to [accuracy] metres.
  double latitude = 5.30;
  double longitude = -4.00;
  double accuracy = 20;

  /// What `getLocationAccuracy` answers: 0 reduced, 1 precise; null throws
  /// in the plugin (a non-int), which the flow reads as not approximate.
  int? accuracyStatus = 1;

  /// When set, `getCurrentPosition` waits for this instead of answering.
  Completer<Object?>? holdPosition;

  /// When set, `requestPermission` waits for this instead of answering.
  Completer<int>? holdRequest;

  /// When set, `getCurrentPosition` fails with this platform error code.
  String? positionError;

  /// What the Settings openers answer.
  bool opens = true;

  final List<String> calls = [];

  /// The settings the last `getCurrentPosition` asked with (its accuracy is
  /// the `LocationAccuracy` index).
  Map<Object?, Object?>? positionSettings;

  int count(String method) => calls.where((c) => c == method).length;

  var _request = 0;

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'isLocationServiceEnabled':
        return service;
      case 'checkPermission':
        return check;
      case 'requestPermission':
        final hold = holdRequest;
        final answer = hold != null
            ? await hold.future
            : requests[_request < requests.length
                  ? _request
                  : requests.length - 1];
        _request++;
        final android = defaultTargetPlatform != TargetPlatform.iOS;
        check = android && answer == deniedForever ? denied : answer;
        return answer;
      case 'getCurrentPosition':
        positionSettings = call.arguments as Map<Object?, Object?>?;
        final hold = holdPosition;
        if (hold != null) return hold.future;
        final error = positionError;
        if (error != null) throw PlatformException(code: error);
        return {
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
          'timestamp': 0,
        };
      case 'getLastKnownPosition':
        final age = lastKnownAge;
        if (age == null) return null;
        return {
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
          'timestamp': AppClock.now().subtract(age).millisecondsSinceEpoch,
        };
      case 'getLocationAccuracy':
        return accuracyStatus;
      case 'openAppSettings' || 'openLocationSettings':
        return opens;
      default:
        return null;
    }
  }

  /// Answer the channel for this test, and forget it after. Also clears
  /// [LocationAccess]'s running read, which a test may leave behind.
  void install(WidgetTester tester) {
    LocationAccess.instance.debugReset();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      _handle,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      LocationAccess.instance.debugReset();
    });
  }
}

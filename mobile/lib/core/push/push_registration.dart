import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/interfaces/device_registration_service_interface.dart';
import '../../services/interfaces/push_notification_service_interface.dart';

/// Orchestrates the app push lifecycle on top of the two seam services:
/// register-on-login-if-granted, ask-after-first-booking, re-register on token
/// refresh, and unregister-on-logout. All work is **best-effort** — it never
/// throws into the booking/auth flows. Design: docs/design/push-notifications-app.md.
class PushRegistration {
  PushRegistration({
    required PushNotificationServiceInterface push,
    required DeviceRegistrationServiceInterface devices,
  })  : _push = push,
        _devices = devices {
    _listenForRefresh();
  }

  final PushNotificationServiceInterface _push;
  final DeviceRegistrationServiceInterface _devices;
  StreamSubscription<String>? _sub;

  static const String _askedKey = 'myweli_push_asked';

  /// On login / app-start (when authed): if permission is already granted, push
  /// the current token to the backend. Never prompts.
  Future<void> registerIfGranted() async {
    try {
      final granted =
          await _push.permissionStatus() == PushPermissionStatus.granted;
      if (!granted) return;
      await _registerCurrentToken();
    } catch (_) {/* best-effort */}
  }

  /// Called after the user's first successful booking. Shows [showRationale]
  /// (the pre-permission sheet) once if permission is undetermined; on accept,
  /// triggers the OS prompt and registers. Guarded so the user is asked once.
  Future<void> maybePromptAfterFirstBooking(
    Future<bool> Function() showRationale,
  ) async {
    try {
      if (await _hasAsked()) return;
      final status = await _push.permissionStatus();
      if (status == PushPermissionStatus.granted) {
        await _registerCurrentToken();
        await _setAsked();
        return;
      }
      if (status == PushPermissionStatus.denied) {
        await _setAsked(); // already decided — don't nag
        return;
      }
      // notDetermined → explain first, then the OS prompt.
      final wantsToEnable = await showRationale();
      await _setAsked();
      if (!wantsToEnable) return;
      if (await _push.requestPermission() == PushPermissionStatus.granted) {
        await _registerCurrentToken();
      }
    } catch (_) {/* best-effort */}
  }

  /// On logout — remove this device's token before the session is cleared.
  Future<void> unregister() async {
    try {
      final token = await _push.getToken();
      if (token == null) return;
      await _devices.unregister(token);
    } catch (_) {/* best-effort */}
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  void _listenForRefresh() {
    _sub ??= _push.onTokenRefresh.listen((token) async {
      try {
        if (await _push.permissionStatus() == PushPermissionStatus.granted) {
          await _devices.register(token, _platform());
        }
      } catch (_) {/* best-effort */}
    });
  }

  Future<void> _registerCurrentToken() async {
    final token = await _push.getToken();
    if (token == null) return;
    await _devices.register(token, _platform());
  }

  Future<bool> _hasAsked() async =>
      (await SharedPreferences.getInstance()).getBool(_askedKey) ?? false;

  Future<void> _setAsked() async =>
      (await SharedPreferences.getInstance()).setBool(_askedKey, true);

  static String _platform() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }
}

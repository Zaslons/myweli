import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/interfaces/device_registration_service_interface.dart';
import '../../services/interfaces/push_notification_service_interface.dart';
import '../utils/app_clock.dart';
import 'push_offer.dart';

/// Orchestrates the app push lifecycle on top of the two seam services:
/// register-on-login-if-granted, ask-after-first-booking, re-register on token
/// refresh, and unregister-on-logout. All work is **best-effort** — it never
/// throws into the booking/auth flows. Design: docs/design/push-notifications-app.md.
///
/// **The client app no longer asks once** (consumer-signin-push.md §2.10,
/// decision 210): [maybeOfferAfterBooking] offers the sheet up to
/// [kPushOfferMax] times, at least [kPushOfferGap] apart, and Préférences can
/// ask at any time ([enableFromSettings]). [maybePromptOnce] is MyWeli Pro's
/// dashboard ask, unchanged.
class PushRegistration {
  PushRegistration({required this._push, required this._devices}) {
    _listenForRefresh();
  }

  final PushNotificationServiceInterface _push;
  final DeviceRegistrationServiceInterface _devices;
  StreamSubscription<String>? _sub;

  static const String _askedKey = 'myweli_push_asked';

  /// The client app's offers of the sheet, and when the last was made
  /// (§2.10). On the phone only.
  static const String _offerCountKey = 'myweli_push_offer_count';
  static const String _offerAtKey = 'myweli_push_offer_at';

  /// Registrations and unregistrations run one after the other, in the order
  /// asked. Signing in starts a registration nobody awaits
  /// (`AuthProvider._syncPush`); a sign-out right after (the phone step's
  /// « Fermer », §2.2) could otherwise see its unregistration land FIRST, and
  /// the signed-out phone would keep receiving the account's pushes.
  Future<void> _serial = Future<void>.value();

  Future<void> _inOrder(Future<void> Function() op) {
    final next = _serial.then((_) => op());
    _serial = next.catchError((Object _) {});
    return next;
  }

  /// On login / app-start (when authed): if permission is already granted, push
  /// the current token to the backend. Never prompts.
  Future<void> registerIfGranted() async {
    try {
      await _inOrder(() async {
        final granted =
            await _push.permissionStatus() == PushPermissionStatus.granted;
        if (!granted) return;
        await _registerCurrentToken();
      });
    } catch (_) {
      /* best-effort */
    }
  }

  /// The client app, after a booking (§2.10, decision 210): register when
  /// granted; offer the sheet while [pushOfferDecision] says so; otherwise
  /// nothing — Préférences keeps the way ([enableFromSettings]).
  ///
  /// The offer is counted BEFORE its answer: every offer counts.
  Future<void> maybeOfferAfterBooking(
    Future<bool> Function() showRationale,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final status = await _push.permissionStatus();
      await _migrateAskedFlag(prefs, status);
      final count = prefs.getInt(_offerCountKey) ?? 0;
      final at = DateTime.tryParse(prefs.getString(_offerAtKey) ?? '');
      final now = AppClock.now();
      switch (pushOfferDecision(
        status: status,
        offerCount: count,
        lastOfferAt: at,
        now: now,
      )) {
        case PushOfferAction.register:
          await _inOrder(_registerCurrentToken);
        case PushOfferAction.none:
          return;
        case PushOfferAction.offer:
          await prefs.setInt(_offerCountKey, count + 1);
          await prefs.setString(_offerAtKey, now.toUtc().toIso8601String());
          if (!await showRationale()) return;
          if (await _push.requestPermission() == PushPermissionStatus.granted) {
            await _inOrder(_registerCurrentToken);
          }
      }
    } catch (_) {
      /* best-effort */
    }
  }

  /// Préférences' « Activer les notifications » (§2.9): the system prompt
  /// directly — the card is the explanation — and the token on « granted ».
  /// Answers what the system said; « not determined » after asking means it
  /// failed (the adapter's answer on error).
  Future<PushPermissionStatus> enableFromSettings() async {
    final status = await _push.requestPermission();
    if (status == PushPermissionStatus.granted) {
      try {
        await _inOrder(_registerCurrentToken);
      } catch (_) {
        /* best-effort */
      }
    }
    return status;
  }

  /// The ask-once flag of the old rule: a phone that set it while the
  /// system still says « not determined » chose « Plus tard » then — one
  /// offer, with no date, so it is offered again after its next booking.
  /// Every other case is decided by the system's answer. The key goes.
  Future<void> _migrateAskedFlag(
    SharedPreferences prefs,
    PushPermissionStatus status,
  ) async {
    if (!prefs.containsKey(_askedKey)) return;
    if ((prefs.getBool(_askedKey) ?? false) &&
        status == PushPermissionStatus.notDetermined &&
        !prefs.containsKey(_offerCountKey)) {
      await prefs.setInt(_offerCountKey, 1);
    }
    await prefs.remove(_askedKey);
  }

  /// Asks for push permission **once** at the first appropriate moment (consumer:
  /// after the first booking; pro: on the first dashboard visit). Shows
  /// [showRationale] if permission is undetermined; on accept, triggers the OS
  /// prompt and registers. Guarded by a persisted flag so we never nag.
  Future<void> maybePromptOnce(Future<bool> Function() showRationale) async {
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
    } catch (_) {
      /* best-effort */
    }
  }

  /// On logout — remove this device's token before the session is cleared.
  Future<void> unregister() async {
    try {
      await _inOrder(() async {
        final token = await _push.getToken();
        if (token == null) return;
        await _devices.unregister(token);
      });
    } catch (_) {
      /* best-effort */
    }
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
      } catch (_) {
        /* best-effort */
      }
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

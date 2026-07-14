import 'package:flutter/foundation.dart';

/// The push routing BRAIN — deliberately free of any Firebase import, so it is
/// unit-testable without a native app (the bridge that talks to
/// `firebase_messaging` lives in services/push/fcm_message_bridge.dart).
///
/// It answers one question: a push (or a tapped notification row) arrived with
/// this `data` — where, if anywhere, does the app go?
///
/// Design: docs/design/push-notifications-app.md.

/// The Android notification channel every MyWeli push lands in.
///
/// **This MUST equal the backend's `FcmV1PushProvider.androidChannelId`** —
/// the server stamps `android.notification.channel_id` with it, and a
/// mismatch would drop background notifications into the unnamed default
/// channel (no name, no importance, invisible in the app's settings).
/// Pinned by a test.
const String kPushChannelId = 'myweli_default';
const String kPushChannelName = 'Notifications Myweli';
const String kPushChannelDescription =
    'Réservations, rappels et mises à jour de vos rendez-vous.';

/// Where a CONSUMER push may navigate (backend: `/appointment/{id}`, falling
/// back to `/bookings`).
const List<String> kConsumerRoutePrefixes = [
  '/appointment/',
  '/bookings',
  '/notifications',
];

/// Where a PRO push may navigate (backend: `/pro/appointment/{id}?salon=…`,
/// falling back to `/pro/appointments`).
const List<String> kProRoutePrefixes = ['/pro/'];

/// The in-app route a push carries, or null when it carries none / an
/// unusable one.
///
/// The route is ALLOWLISTED by prefix: a payload can only send the user
/// somewhere this app surface actually owns. Anything else — junk, a foreign
/// surface's route, a hostile string — is dropped rather than navigated to.
String? routeFromPushData(
  Map<String, Object?> data, {
  required List<String> allowedPrefixes,
}) {
  final raw = data['route'];
  if (raw is! String) return null;
  final route = raw.trim();
  if (route.isEmpty || !route.startsWith('/')) return null;
  final allowed = allowedPrefixes.any(route.startsWith);
  return allowed ? route : null;
}

/// The salon a PRO push belongs to: the `providerId` data key, else the
/// route's `?salon=` (the in-app feed row carries only the route, so the
/// salon rides in it — backend `SalonNotifier`).
String? providerIdFromPushData(Map<String, Object?> data) {
  final direct = data['providerId'];
  if (direct is String && direct.trim().isNotEmpty) return direct.trim();

  final raw = data['route'];
  if (raw is! String) return null;
  final salon = Uri.tryParse(raw)?.queryParameters['salon'];
  return (salon == null || salon.isEmpty) ? null : salon;
}

/// Turns a push/notification payload into navigation.
///
/// Three things make this non-trivial, and each is handled here rather than in
/// the UI:
///
/// 1. **Cold start.** A tap can launch the app: the router isn't mounted and
///    the session isn't restored yet. The payload is BUFFERED and replayed by
///    [flushPending] once the app is authenticated — otherwise the deep link
///    would be eaten by the splash/login redirect.
/// 2. **Multi-salon (R6).** A pro may be signed in on another salon than the
///    booking's. [ensureSalon] switches first (which also resets every
///    salon-scoped provider), and a failed switch lands on
///    [salonSwitchFallbackRoute] instead of a booking the active scope cannot
///    resolve.
/// 3. **Trust.** Routes are prefix-allowlisted ([routeFromPushData]).
class PushMessageHandler {
  PushMessageHandler({
    required this.navigate,
    required this.allowedRoutePrefixes,
    this.ensureSalon,
    this.isAuthenticated,
    this.salonSwitchFallbackRoute,
  });

  /// Pushes the route (the app's router — injected so this class stays pure).
  final Future<void> Function(String route) navigate;

  final List<String> allowedRoutePrefixes;

  /// Pro only: make [providerId] the active salon. Returns false when the
  /// account can't act on it (revoked, unknown).
  final Future<bool> Function(String providerId)? ensureSalon;

  /// Null → treat as authenticated (the consumer app before session restore
  /// passes a real predicate; tests may omit it).
  final bool Function()? isAuthenticated;

  /// Where to land when [ensureSalon] fails (pro: `/pro/dashboard`).
  final String? salonSwitchFallbackRoute;

  Map<String, Object?>? _pending;

  @visibleForTesting
  bool get hasPending => _pending != null;

  /// Handle one payload (a tapped push, a launch message, or a foreground
  /// notification tap). Best-effort: never throws into the caller.
  Future<void> handleData(Map<String, Object?> data) async {
    try {
      final route = routeFromPushData(
        data,
        allowedPrefixes: allowedRoutePrefixes,
      );
      if (route == null) return;

      // Not signed in yet (cold-start tap) → keep the WHOLE payload, so the
      // salon switch replays too.
      if (isAuthenticated != null && !isAuthenticated!()) {
        _pending = data;
        return;
      }

      final providerId = providerIdFromPushData(data);
      final switcher = ensureSalon;
      if (providerId != null && switcher != null) {
        final ok = await switcher(providerId);
        if (!ok) {
          final fallback = salonSwitchFallbackRoute;
          if (fallback != null) await navigate(fallback);
          return;
        }
      }

      await navigate(route);
    } catch (_) {
      // A notification tap must never crash the app.
    }
  }

  /// Replay a buffered cold-start tap (called when the session lands).
  Future<void> flushPending() async {
    final data = _pending;
    if (data == null) return;
    _pending = null;
    await handleData(data);
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../utils/salon_id.dart';
import 'push_message_handler.dart';

/// A [PushMessageHandler] whose buffered tap replays only once the app has
/// **landed**: signed in, AND the router past the screens that hand over with
/// a `go`.
///
/// Why "signed in" alone was not enough (docs/design/pro-open-animation.md
/// §2.6): a notification that cold-starts the Pro app is buffered, and the
/// session load signs in DURING the splash — so the replay pushed the page
/// above the splash, and the splash's `context.go` then replaced the whole
/// page stack, the pushed page with it. The sign-in screen does the same
/// after a login. A `go` is right for those screens and wrong for anything
/// pushed above them, so the replay waits for the `go` instead.
///
/// [launchPaths] are those screens (`ProRouter.launchPaths`). Nothing can
/// strand the user here: the splash routes on its own (bounded), and a tap
/// that never replays leaves the user where the splash put them.
///
/// The gate is also the `isAuthenticated` predicate, so a tap that arrives
/// while a launch screen is up is buffered rather than pushed — a warm tap
/// on a signed-in screen navigates at once, as before.
PushMessageHandler landedPushHandler({
  required GoRouter router,
  required Listenable session,
  required bool Function() isSignedIn,
  required Set<String> launchPaths,
  required List<String> allowedRoutePrefixes,
  Future<bool> Function(SalonId providerId)? ensureSalon,
  String? salonSwitchFallbackRoute,
}) {
  bool landed() {
    final at = router.routerDelegate.currentConfiguration;
    // Empty before the router is mounted — a `getInitialMessage` tap lands
    // here before `runApp`, and must wait like any other.
    return at.isNotEmpty && !launchPaths.contains(at.uri.path);
  }

  bool ready() => isSignedIn() && landed();

  final handler = PushMessageHandler(
    // Issued, not awaited: a push's future completes when the page is POPPED,
    // and `FcmMessageBridge.init` awaits the launch tap's handling — which
    // `main_pro.dart` awaits before `runApp`.
    navigate: (route) async {
      unawaited(router.push<void>(route));
    },
    allowedRoutePrefixes: allowedRoutePrefixes,
    isAuthenticated: ready,
    ensureSalon: ensureSalon,
    salonSwitchFallbackRoute: salonSwitchFallbackRoute,
  );

  void replay() {
    if (!ready()) return;
    // A microtask, not inline: this runs inside the router delegate's own
    // notification, and a `push` from there would re-enter the router while
    // it is still applying the `go` that woke us.
    scheduleMicrotask(() => unawaited(handler.flushPending()));
  }

  session.addListener(replay);
  router.routerDelegate.addListener(replay);
  return handler;
}

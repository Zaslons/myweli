import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/auth/pro_splash_screen.dart';

export 'open_timeline.dart';

/// Shared harness for the Pro splash (docs/design/pro-open-animation.md):
/// a session the test resolves by hand and the three destinations. The
/// asset's own timeline is [OpenTimeline] (open_timeline.dart, re-exported).
///
/// Callers set `serviceLocator.authService` once in `setUpAll` — the base
/// constructor reads it (and it is a `late final`, so only once per file).

/// A [ProAuthProvider] whose session load finishes when the test says so —
/// in the two stages the real one has: the stored session read ([restore]),
/// then the live membership refresh (the rest of [load]).
///
/// The base constructor starts the one load (as `main_pro.dart` does) and
/// keeps it as `ready`; [loadCalls] counts that one too, so tests compare
/// against a baseline.
class FakeProSession extends ProAuthProvider {
  FakeProSession({this.signedIn = false, this.staff = false});

  /// What the stored session says. [signIn] flips it, as a login would.
  bool signedIn;
  final bool staff;

  /// Complete it to finish the whole load — restore AND live refresh.
  final Completer<void> load = Completer<void>();

  /// Complete it to finish only the restore: the stored session is read and
  /// the live refresh is still running (or hanging).
  final Completer<void> restore = Completer<void>();

  int loadCalls = 0;

  /// The salons a replayed notification switched to.
  final List<String> switchedTo = [];

  @override
  Future<void> loadCurrentProvider() {
    loadCalls++;
    return load.future;
  }

  @override
  Future<void> get restored => Future.any([restore.future, load.future]);

  @override
  bool get isAuthenticated => signedIn;

  @override
  bool get isStaff => staff;

  /// The rejoin gate holds the session — signed in, no salon
  /// (docs/design/pro-rejoin-gate.md).
  bool rejoin = false;

  @override
  bool get rejoinPending => rejoin;

  @override
  Future<bool> switchSalon(String salonId) async {
    switchedTo.add(salonId);
    return true;
  }

  /// The session signs in and says so — what the restore, or a login, does.
  void signIn() {
    signedIn = true;
    notifyListeners();
  }

  /// The gate is left into a salon and says so — what `completeRejoin`
  /// does once the joined salon's membership has landed.
  void leaveRejoin() {
    rejoin = false;
    notifyListeners();
  }
}

/// `/pro/splash` plus the four places it can send the user, each a plain
/// « route:… » text so a test can tell them apart — and the booking page a
/// notification opens (« route:appointment `id` »).
GoRouter proSplashRouter() => GoRouter(
  initialLocation: '/pro/splash',
  routes: [
    GoRoute(path: '/pro/splash', builder: (_, _) => const ProSplashScreen()),
    for (final name in ['login', 'dashboard', 'staff', 'invitations'])
      GoRoute(
        path: '/pro/$name',
        builder: (_, _) => Scaffold(body: Text('route:$name')),
      ),
    GoRoute(
      path: '/pro/appointment/:id',
      builder: (_, state) => Scaffold(
        body: Text('route:appointment ${state.pathParameters['id']}'),
      ),
    ),
  ],
);

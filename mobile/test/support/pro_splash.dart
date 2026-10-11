import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/auth/pro_splash_screen.dart';

/// Shared harness for the Pro splash (docs/design/pro-open-animation.md):
/// a session the test resolves by hand, the three destinations, and the
/// asset's own timeline.
///
/// Callers set `serviceLocator.authService` once in `setUpAll` — the base
/// constructor reads it (and it is a `late final`, so only once per file).

/// A [ProAuthProvider] whose session load finishes when the test says so.
///
/// The base constructor already starts one load (as `main_pro.dart` does);
/// [loadCalls] counts that one too, so tests compare against a baseline.
class FakeProSession extends ProAuthProvider {
  FakeProSession({this.signedIn = false, this.staff = false});

  final bool signedIn;
  final bool staff;

  /// Complete it to finish `loadCurrentProvider()`.
  final Completer<void> load = Completer<void>();
  int loadCalls = 0;

  @override
  Future<void> loadCurrentProvider() {
    loadCalls++;
    return load.future;
  }

  @override
  bool get isAuthenticated => signedIn;

  @override
  bool get isStaff => staff;
}

/// `/pro/splash` plus the three places it can send the user, each a plain
/// « route:… » text so a test can tell them apart.
GoRouter proSplashRouter() => GoRouter(
  initialLocation: '/pro/splash',
  routes: [
    GoRoute(path: '/pro/splash', builder: (_, _) => const ProSplashScreen()),
    for (final name in ['login', 'dashboard', 'staff'])
      GoRoute(
        path: '/pro/$name',
        builder: (_, _) => Scaffold(body: Text('route:$name')),
      ),
  ],
);

/// The asset's markers, as the screen reads them — so the tests follow the
/// file rather than restating its numbers.
class ProOpenTimeline {
  ProOpenTimeline._(this._json);

  factory ProOpenTimeline.load() => ProOpenTimeline._(
    jsonDecode(File(ProSplashScreen.asset).readAsStringSync())
        as Map<String, dynamic>,
  );

  final Map<String, dynamic> _json;

  num get _fps => _json['fr'] as num;

  Map<String, dynamic> _marker(String name) => (_json['markers'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((m) => m['cm'] == name);

  /// How long the intro plays — the earliest the splash may route.
  Duration get intro {
    final frames = _marker(ProSplashScreen.introMarker)['dr'] as num;
    return Duration(microseconds: (frames / _fps * 1e6).round());
  }

  /// The composition's last frame (`op`).
  num get endFrame => _json['op'] as num;

  /// A controller value as a composition frame (±0.01: lottie ends the
  /// composition at `op - 0.01`).
  double frameOf(double progress) => progress * endFrame;

  /// First frame of the mark redraw loop.
  num get loopStartFrame => _marker(ProSplashScreen.loopMarker)['tm'] as num;

  /// The `wordmark` hold, in frames.
  (num, num) get wordmarkFrames {
    final m = _marker(ProSplashScreen.wordmarkMarker);
    return (m['tm'] as num, (m['tm'] as num) + (m['dr'] as num));
  }
}

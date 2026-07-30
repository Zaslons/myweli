import 'package:flutter/material.dart';

/// Has the user asked the OS to stop moving the screen? (SYSTEM.md §9, §13.)
///
/// **Two flags, because one platform each sets one of them.**
///
///   * **Android** reports `disableAnimations` — and only when *Transition
///     animation scale* is exactly 0. It rides `MediaQueryData`, so reading it
///     through `MediaQuery` rebuilds on change for free.
///   * **iOS** reports `reduceMotion`. `FlutterViewController.mm:2159` maps
///     "Reduce Motion" to `kReduceMotion`; `kDisableAnimations` appears in no
///     Darwin embedder, and `grep -rn "reduceMotion" packages/flutter/lib/`
///     returns **zero** — the framework reads it nowhere. §9 promised this
///     behaviour to iOS users and, until A8, delivered it to none of them.
///
/// **What the framework already handles, so callers should not.** Route
/// transitions, `Hero`, and every implicit `AnimatedX` run plain controllers,
/// which `_animateToInternal` scales to 5 % when
/// `SemanticsBinding.instance.disableAnimations` is set
/// (`animation_controller.dart:651`). Do **not** hand-wire those — you would be
/// re-implementing something that already works, and only on Android.
///
/// Reach for this only where the framework cannot help:
///
///   * anything driven by `repeat()`, which calls `_startSimulation` directly
///     and never sees the scale — Lottie's ticker, `CircularProgressIndicator`;
///   * **involuntary** movement, where the app scrolls or advances the page
///     rather than the user (`Scrollable.ensureVisible`, `PageController`).
bool reduceMotionOf(BuildContext context) {
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return true;
  final scope = context
      .dependOnInheritedWidgetOfExactType<_ReduceMotionScope>();
  // No scope above us — a bare `MaterialApp` in a widget test, or an app root
  // that has not been wrapped. Read the value straight from the dispatcher:
  // correct, just not reactive. **Fail-safe, never fail-broken** — a missing
  // scope must cost a rebuild, not the behaviour itself.
  return scope?.reduceMotion ??
      WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .reduceMotion;
}

/// Makes the **iOS** half of [reduceMotionOf] reactive. Install once per app
/// root, above `MaterialApp`.
///
/// `PlatformDispatcher.accessibilityFeatures` is not an `InheritedWidget`, and
/// `MediaQuery` will not stand in for it: `MediaQueryData` has no `reduceMotion`
/// field, so `_MediaQueryFromViewState._updateData` computes an *equal* data
/// object when only that flag moves and never calls `setState`. Without this
/// widget, a user who toggles Reduce Motion in Settings and returns to the app
/// keeps the animation until something else happens to rebuild — and on the
/// splash, which builds once, nothing else ever does.
///
/// Enforced by `test/a11y/motion_test.dart`, which discovers `lib/main*.dart`
/// by glob rather than by list, so a new root is covered the day it lands.
class ReduceMotionObserver extends StatefulWidget {
  const ReduceMotionObserver({super.key, required this.child});

  final Widget child;

  @override
  State<ReduceMotionObserver> createState() => _ReduceMotionObserverState();
}

class _ReduceMotionObserverState extends State<ReduceMotionObserver>
    with WidgetsBindingObserver {
  static bool _read() => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .reduceMotion;

  late bool _reduceMotion = _read();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // Not optional: the binding holds observers forever, so a missed removal
    // means `didChangeAccessibilityFeatures` calls `setState` on a defunct
    // State the next time the flag moves. Proven by deleting this line and
    // watching `motion_test.dart`'s tear-down assertion throw.
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() {
    final next = _read();
    if (next != _reduceMotion) setState(() => _reduceMotion = next);
  }

  @override
  Widget build(BuildContext context) =>
      _ReduceMotionScope(reduceMotion: _reduceMotion, child: widget.child);
}

class _ReduceMotionScope extends InheritedWidget {
  const _ReduceMotionScope({required this.reduceMotion, required super.child});

  final bool reduceMotion;

  @override
  bool updateShouldNotify(_ReduceMotionScope oldWidget) =>
      oldWidget.reduceMotion != reduceMotion;
}

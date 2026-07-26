import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/single_child_widget.dart';

import '../support/pump_app.dart';

/// A8 — the reduce-motion harness (SYSTEM.md §9, §21 row 20).
///
/// **Why `accessibilityFeaturesTestValue` and not a `MediaQuery` override.**
/// There are three levers and only this one moves both consumers:
///
///   * `MediaQuery(data: …copyWith(disableAnimations: true))` reaches widgets
///     that read `MediaQuery.disableAnimationsOf` — but **not**
///     `SemanticsBinding.instance.disableAnimations`, which is what the
///     framework's own 5 % scaling reads. A gate built on it would test our
///     code and silently skip the framework path.
///   * `debugSemanticsDisableAnimations` is the mirror image: it moves the
///     binding and never reaches `MediaQuery`. It is also a framework global
///     with no auto-reset.
///   * `platformDispatcher.accessibilityFeaturesTestValue` feeds BOTH —
///     `MediaQuery.fromView` sources it (`media_query.dart:296`) and the setter
///     fires `onAccessibilityFeaturesChanged`, which `SemanticsBinding` wires.
///
/// The flag is **process-global**, so the tear-down is not optional and lives
/// here rather than in each caller — the same reason `golden.dart` refuses to
/// load fonts from a global `flutter_test_config.dart`.
Future<void> pumpWithReducedMotion(
  WidgetTester tester,
  Widget child, {
  List<SingleChildWidget>? providers,
  bool disableAnimations = true,
  bool reduceMotion = true,
}) async {
  setReducedMotion(
    tester,
    disableAnimations: disableAnimations,
    reduceMotion: reduceMotion,
  );
  await pumpApp(tester, providers: providers, home: Scaffold(body: child));
  await tester.pump();
}

/// Raise the OS flags **without** pumping — the mid-session case.
///
/// Split out of [pumpWithReducedMotion] because *when* the flag arrives is a
/// distinction the gate has to draw. A user who toggles "Reduce Motion" in
/// Settings and comes back finds a tree that is already built:
///
///   * the **Android** half rides `MediaQueryData.disableAnimations`, so
///     `_MediaQueryFromViewState.didChangeAccessibilityFeatures` recomputes the
///     data, sees it differ, and `setState`s — reactivity for free;
///   * the **iOS** half does not. `MediaQueryData` has no `reduceMotion` field
///     at all (`grep -n reduceMotion media_query.dart` → 0 hits), so
///     `_updateData`'s `if (newData != _data)` is false and nothing rebuilds.
///
/// So a mid-session gate must raise **only** `reduceMotion`, or `MediaQuery`
/// answers it and the observer under test is never exercised.
///
/// The setter dispatches synchronously (`window.dart:536-539` calls
/// `onAccessibilityFeaturesChanged` inline), so the very next `pump()` renders
/// the reaction.
void setReducedMotion(
  WidgetTester tester, {
  bool disableAnimations = true,
  bool reduceMotion = true,
}) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(
    disableAnimations: disableAnimations,
    reduceMotion: reduceMotion,
  );
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

/// One frame at 60 fps — **the discriminator, and the arithmetic behind it.**
///
/// Under the flag the framework runs a `normal` controller at **5 %** of its
/// duration, not at zero: `animation_controller.dart:651`, and the comment
/// three lines above says why zero is refused (*"the common pattern of an
/// eternally repeating animation might cause an endless loop"*).
///
/// So for §9's 200 ms `motionBase`: reduced = 10 ms, full = 200 ms. A single
/// 16 ms frame is **past** the first and **nowhere near** the second — a 20×
/// margin on both sides, which is why this is not flaky. Pumping
/// `Duration.zero` (a bare `pump()`) would sit at t=0 and value 0.0 in *both*
/// modes, and prove nothing.
const Duration kOneFrame = Duration(milliseconds: 16);

/// Assert that [child] animates with motion on and **does not** with motion off.
///
/// **Two-legged on purpose.** The motion-OFF leg alone is vacuous: a widget that
/// never animated at all would sail through it. The motion-ON leg is what makes
/// the gate mean something — it proves there was motion here to stop.
///
/// This is the same trap `_a11y.dart` names for text scale (*"unbounded, nothing
/// can overflow and the gate is vacuous"*) and the same distinction
/// `app_snack_bar_test.dart:52` draws: what we ASKED for is not what happened.
///
/// [trigger] must start the animation (a tap, a `setState`); [measure] returns
/// the geometry that changes — a height, a width, an offset.
Future<void> expectHonoursReducedMotion(
  WidgetTester tester, {
  required Widget Function() build,
  required Future<void> Function(WidgetTester) trigger,
  required double Function(WidgetTester) measure,
  List<SingleChildWidget>? providers,
}) async {
  // ── Leg 1: motion ON. One frame in, it must be MID-FLIGHT.
  await pumpApp(tester, providers: providers, home: Scaffold(body: build()));
  await tester.pump();
  final restingOn = measure(tester);

  await trigger(tester);
  await tester.pump(); // start the tween
  await tester.pump(kOneFrame);
  final oneFrameIn = measure(tester);

  await tester.pump(const Duration(milliseconds: 400)); // well past any token
  final settledOn = measure(tester);

  expect(
    settledOn,
    isNot(closeTo(restingOn, 0.5)),
    reason: 'the trigger changed nothing — this gate has no subject, and its '
        'reduced-motion leg would pass for a widget that never animates',
  );
  expect(
    oneFrameIn,
    isNot(closeTo(settledOn, 0.5)),
    reason: 'one 16ms frame already reached the end state WITH motion on, so '
        'the reduced-motion leg below cannot distinguish anything. Either the '
        'animation is shorter than a frame or it is not running.',
  );

  // ── Leg 2: motion OFF. The same single frame must already be settled.
  await pumpWithReducedMotion(tester, build(), providers: providers);
  await trigger(tester);
  await tester.pump();
  await tester.pump(kOneFrame);
  final oneFrameOff = measure(tester);

  expect(
    oneFrameOff,
    closeTo(settledOn, 0.5),
    reason: 'a user who asked the OS to stop animating still watched this move '
        '(§9). One 60fps frame must land on the end state.',
  );
}

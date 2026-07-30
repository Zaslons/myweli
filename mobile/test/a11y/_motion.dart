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

// `expectHonoursReducedMotion` used to live here — 48 lines of two-legged
// geometry harness carrying this file's most emphatic doctrine, and **zero
// call sites**. It is deleted, for the reason A7's fix commit deleted
// `FieldErrors.unvalidatedKeys`: a zero-caller API is not infrastructure, it
// is a claim about work that was never done.
//
// The doctrine survives where it belongs — in the gates themselves. Every
// reduced-motion assertion in `motion_test.dart` is two-legged against the
// measure that actually discriminates for its subject: `hasScheduledFrame` for
// the loader, `PageController.page` for the story reel (a generic geometry
// probe would have passed a reel that jumped for everybody), and the presence
// of the caption at 2x text for the loader's bound. The abstraction fit none
// of them, which is precisely why it had no callers.

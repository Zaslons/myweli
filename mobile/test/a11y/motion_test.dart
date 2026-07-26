import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:myweli/widgets/common/brand_loader.dart';

import '../support/pump_app.dart';
import '_motion.dart';

/// A8 — the app listens when the OS says stop (SYSTEM.md §9, §21 row 20).
///
/// **Written before the sweep, and watched fail.** The three previous slices
/// each swept first and gated after, and each time the gate either missed the
/// defect class or did not exist. These assertions were red at `31ce0e8` — the
/// reds are in the PR — and the code that makes them green comes in the NEXT
/// commit.
///
/// What the framework already does, so the gate does not re-prove it: route
/// transitions, `Hero` and every implicit `AnimatedX` collapse to 5 %
/// automatically, because they run plain controllers that reach the scale at
/// `animation_controller.dart:651`. What it never does is `repeat()` — which
/// bypasses `_animateToInternal` entirely. So everything below targets the
/// manual half: §9's *"looping/decorative animation stops"*.
void main() {
  group('§9 — looping animation stops (the half the framework will not do)',
      () {
    testWidgets('BrandLoader keeps scheduling frames forever with motion ON',
        (tester) async {
      // The control. Without it the assertion below could pass on a loader that
      // never animated at all — and this is also the reason 18 test files
      // hand-roll `settle()` instead of using `pumpAndSettle`.
      await pumpApp(tester, home: const Scaffold(body: BrandLoader()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'the infinite Lottie is the subject of this gate — if it '
              'stopped on its own, the reduced-motion assertion proves nothing');
    });

    testWidgets('…and STOPS under reduced motion', (tester) async {
      await pumpWithReducedMotion(tester, const BrandLoader());
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: '§9: looping/decorative animation stops. `repeat()` bypasses '
              'the framework 5% scale entirely, so the widget must read the '
              'flag itself — nothing upstream will do it.');
    });

    testWidgets('the loading state still SAYS it is loading', (tester) async {
      // Freezing the mark silently would delete the only "something is
      // happening" signal. The French label carries it instead — and it is the
      // first thing a screen reader has ever been given here, in either mode.
      await pumpWithReducedMotion(tester, const BrandLoader());
      await tester.pump();

      expect(find.text('Chargement…'), findsOneWidget,
          reason: 'a frozen logo is indistinguishable from a broken screen');
    });

    testWidgets('the Lottie is told not to animate, not merely hidden',
        (tester) async {
      await pumpWithReducedMotion(tester, const BrandLoader());
      await tester.pump();

      final lottie = tester.widget<LottieBuilder>(find.byType(LottieBuilder));
      expect(lottie.animate, isFalse,
          reason: 'still frame, not an invisible one that keeps ticking');
    });
  });

  // ── The story-dwell bug is NOT gated here, deliberately. ────────────────
  //
  // `story_viewer` runs a 6-second reading time on a default-behaviour
  // controller via `.forward()`, which by SDK reading should hit the 0.05 scale
  // (`animation_controller.dart:651`) and collapse the dwell to 300ms.
  //
  // Two attempts to gate it both failed to fail:
  //   1. building a controller with `AnimationBehavior.preserve` and asserting
  //      it is unscaled — that tests the SDK, not us, and passes whatever
  //      `story_viewer` does;
  //   2. pumping the real `StoryViewer` and counting `onViewed` calls — GREEN
  //      at base, so either the scale is not reached on this path or `onViewed`
  //      does not fire per advance.
  //
  // A gate that will not go red is not a gate, and the bug is not confirmed
  // until something reproduces it. It is carried as an open question in
  // docs/design/mobile-a8-motion.md rather than asserted here or "fixed"
  // blind — fixing an unreproduced bug is how a slice ships a change nobody
  // can justify.
}

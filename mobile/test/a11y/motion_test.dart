import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:myweli/screens/splash/splash_screen.dart';
import 'package:myweli/screens/stories/story_viewer.dart';
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

    testWidgets('there is no Lottie at all — a still brand mark instead',
        (tester) async {
      // **This assertion used to read `lottie.animate, isFalse`, and it was
      // wrong on a point no test could see.** `animate: false` really does stop
      // the ticker, so it passed, and the sweep shipped it. Then the golden was
      // taken: frame 0 of a draw-on loader is an EMPTY CANVAS, so "freeze the
      // mark" had frozen a blank box with a caption floating under it. The
      // property was right and the pixels were not.
      //
      // What replaces it is the mark the animation draws towards — the same
      // brand asset, held still. Asserting its ABSENCE is what keeps a future
      // `animate: false` from quietly coming back.
      await pumpWithReducedMotion(tester, const BrandLoader());
      await tester.pump();

      expect(find.byType(LottieBuilder), findsNothing,
          reason: 'a Lottie under the flag is either ticking or blank — '
              'neither is a still mark');
      expect(find.byType(SvgPicture), findsOneWidget,
          reason: 'the loading state must still SHOW the brand, not just '
              'stop moving');
    });
  });

  /// The first group sets **both** OS flags, so it cannot tell the two halves
  /// apart. This one sets only the half the framework ignores.
  ///
  /// `FlutterViewController.mm:2159` maps iOS "Reduce Motion" to `kReduceMotion`;
  /// `kDisableAnimations` appears in no Darwin embedder, and
  /// `grep -rn "reduceMotion" packages/flutter/lib/` returns **zero**. So on iOS
  /// §9's promise is kept by nothing at all unless we keep it ourselves.
  group('§9 on iOS — the flag the framework reads nowhere', () {
    testWidgets('the loader stops on the iOS flag ALONE', (tester) async {
      await pumpWithReducedMotion(tester, const BrandLoader(),
          disableAnimations: false);
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'every iOS user who set Reduce Motion gets the animation '
              'anyway if this reads MediaQuery alone — MediaQueryData has no '
              'reduceMotion field to read.');
    });

    testWidgets('raising it MID-SESSION stops a loader already on screen',
        (tester) async {
      // The realistic path: the spinner is up, the user leaves for Settings,
      // turns Reduce Motion on, and comes back. Nothing rebuilds on its own —
      // `_updateData`'s `if (newData != _data)` is false when only
      // `reduceMotion` moved, because `MediaQueryData` does not carry it.
      await pumpApp(tester, home: const Scaffold(body: BrandLoader()));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'the control: it must be animating before the flag lands, or '
              'the assertion below is about nothing');

      setReducedMotion(tester, disableAnimations: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'this is the assertion that needs an observer. Reading the '
              'flag at build time passes the test above and fails this one — '
              'which is exactly the difference the observer exists to make.');
    });

    testWidgets('the observer unregisters itself when the tree goes away',
        (tester) async {
      // A6 found three leaked controllers, and the test that was supposed to
      // catch one of them stayed green when the `dispose()` was deleted. The
      // binding holds observers for the life of the process, so a missed
      // `removeObserver` means the next flag change calls `setState` on a
      // defunct State — which throws, from inside a platform callback, far from
      // the widget that caused it.
      await pumpApp(tester, home: const Scaffold(body: BrandLoader()));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(() => setReducedMotion(tester, disableAnimations: false),
          returnsNormally,
          reason: 'the flag reached a State that no longer exists — '
              '`_ReduceMotionObserverState.dispose` is not removing itself '
              'from the binding');
    });

    test('every app root installs the observer that makes that possible', () {
      // Discovered, not listed: a fourth `main_*.dart` is covered the day it
      // lands rather than the day someone remembers to add it here.
      final roots = Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => RegExp(r'main(_\w+)?\.dart$').hasMatch(f.path))
          .toList();
      expect(roots, isNotEmpty,
          reason: 'no app root found — this test is resolving paths from the '
              'wrong directory and would pass on an empty set');

      final missing = roots
          .where((f) => !f.readAsStringSync().contains('ReduceMotionObserver'))
          .map((f) => f.path)
          .toList();

      expect(missing, isEmpty,
          reason: 'the iOS flag is not an InheritedWidget, so a root without '
              'the observer honours it only on the next rebuild that happens '
              'to occur. Correct, but not reactive — and on the splash, which '
              'builds once, "the next rebuild" never comes.');
    });
  });

  /// §13 — and the gap A8 found on the way past.
  ///
  /// `BrandLoader` has **no `Semantics` at all** today, at 68 call sites. With
  /// motion on it is a moving mark and nothing else: a screen reader reaches it
  /// and says nothing, so the app's most common transient state is silent. That
  /// is not caused by reduced motion, but freezing the mark would make it worse,
  /// so the label is not conditional on the flag — only the *visible* text is.
  group('§13 — the loader says what it is, in BOTH modes', () {
    testWidgets('with motion ON, the moving mark still has a label',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, home: const Scaffold(body: BrandLoader()));
      await tester.pump();

      expect(find.bySemanticsLabel('Chargement…'), findsOneWidget,
          reason: 'a purely visual loading state excludes the users §13 is '
              'written for — and this half has nothing to do with motion');
      handle.dispose();
    });

    testWidgets('under reduced motion, EXACTLY one node says it',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWithReducedMotion(tester, const BrandLoader());

      expect(find.bySemanticsLabel('Chargement…'), findsOneWidget,
          reason: 'the visible text and the wrapper must not BOTH announce. '
              'This finder returns two nodes if the label is added without '
              'excluding the Text beneath it — which is the natural way to '
              'write it, and is why the count is asserted rather than presence');
      handle.dispose();
    });
  });

  /// The scope is what makes the flag *reactive*; it must not be what makes the
  /// widget *correct*. 100+ widget tests pump a bare `MaterialApp`, and so may
  /// the next app root — a design that reads the flag only through our own shell
  /// fails silently everywhere the shell is absent.
  group('the loader is correct outside our own shell', () {
    testWidgets('a bare MaterialApp still honours the flag', (tester) async {
      setReducedMotion(tester);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BrandLoader())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'no ReduceMotionObserver above it, and it must still stop. '
              'Fail-safe, not fail-broken: a missing scope costs reactivity, '
              'never correctness.');
    });
  });

  /// The three defects the adversarial review found, gated before they were
  /// fixed — every one of them in code A8 itself wrote, and every one of them
  /// in a reduced-motion path that `BrandLoader` gates could never reach.
  ///
  /// That is the lesson of this group: ①–①c all pumped ONE widget. Six
  /// `reduceMotionOf` call sites shipped, five of them asserted by nothing.
  group('§9.1 — the OTHER call sites, which nothing was pumping', () {
    testWidgets('the story reel ADVANCES under the flag instead of throwing',
        (tester) async {
      // `Duration.zero` is legal for `Scrollable.ensureVisible`
      // (`scroll_position.dart:872` jumps explicitly) and **illegal** for
      // `PageController`: `animateToPage` → `position.animateTo` →
      // `DrivenScrollActivity`, whose constructor is
      // `assert(duration > Duration.zero)` (`scroll_activity.dart:705`).
      // `_PagePosition` overrides `ensureVisible` and `jumpTo`, never
      // `animateTo`, so nothing short-circuits it.
      //
      // A8 read one API's behaviour and generalised it to the other. The cost
      // is that every story reel throws on its first advance for exactly the
      // users the slice was written for.
      await pumpWithReducedMotion(
        tester,
        const SizedBox.shrink(),
      );
      await tester.pumpWidget(
        wrapApp(
          home: const StoryViewer(
            stories: [
              StoryItem(
                id: 'a',
                title: 'Un',
                assetPath: 'assets/images/stories/promo_weekend.svg',
              ),
              StoryItem(
                id: 'b',
                title: 'Deux',
                assetPath: 'assets/images/stories/nouveaux_salons.svg',
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      // Tap the right 65 % — `_onTapDown`'s advance.
      await tester.tapAt(const Offset(700, 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull,
          reason: 'the reel must advance instantly, not assert. Zero duration '
              'is a jump for ensureVisible and a crash for PageController.');
    });

    testWidgets('the splash SHOWS the brand instead of a blank screen',
        (tester) async {
      // The bug ②/⑤ already fixed in `BrandLoader`, shipped one file over:
      // `animate: false` holds composition frame 0, and in
      // `myweli_loader_mixed.json` every layer is either opacity 0 at t=0 or
      // not in-point until frame 54. Under the flag the splash was
      // `#FAFAFA` and nothing else for the full 3800 ms hold.
      //
      // Asserting the CONTROLLER is what makes this a gate rather than a
      // restatement: a pinned progress is the only thing that both stops the
      // ticker and lands on a frame with ink in it.
      await pumpWithReducedMotion(tester, const SizedBox.shrink());
      await tester.pumpWidget(wrapApp(home: const SplashScreen()));
      await tester.pump();

      final lottie = tester.widget<LottieBuilder>(find.byType(LottieBuilder));
      expect(lottie.controller, isNotNull,
          reason: 'frame 0 of this composition is an EMPTY canvas — freezing '
              'it renders a blank splash. The progress must be pinned to a '
              'frame that has the mark on it.');
      expect(lottie.controller!.value, greaterThan(0.0),
          reason:
              'pinned to frame 0 is the same blank screen with extra steps');
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'and it must still not animate');
    });

    testWidgets('the caption never overflows a box too small to hold it',
        (tester) async {
      // `LoadingIndicator` never passes `fast`, so all ~50 of its call sites
      // take the caption branch — including a 60×60 avatar placeholder
      // (`artist_selection_screen.dart:375`). 40 mark + 8 gap + 16 line = 64,
      // and « Chargement… » is wider than 60 so it wraps to 32: an ~20px
      // RenderFlex overflow while avatars load.
      //
      // Fixing the one call site is not enough — the next 60px box re-creates
      // it. The widget measures instead.
      await pumpWithReducedMotion(
        tester,
        const SizedBox(width: 60, height: 60, child: BrandLoader()),
      );
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'a loading state that throws is worse than one that does '
              'not explain itself');
      expect(find.text('Chargement…'), findsNothing,
          reason: 'no room for it — and the Semantics label still says it, '
              'which is the half that matters for §13');
    });

    testWidgets('…and still shows it when there IS room, at 2× text',
        (tester) async {
      // The other half: a computed bound that under-provisions is register
      // row 15's exact failure, so the gate checks the scale that breaks it.
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpWithReducedMotion(
        tester,
        const SizedBox(width: 200, height: 200, child: BrandLoader()),
      );
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'the caption must fit at 2× in a box that claims to hold it');
      expect(find.text('Chargement…'), findsOneWidget,
          reason: 'over-provisioning is the other way a computed bound rots — '
              'a 200px box has room for a 48px mark and one line of text');
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

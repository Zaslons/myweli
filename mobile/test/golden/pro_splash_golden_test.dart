import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:provider/provider.dart';

import '../support/golden.dart';
import '../support/pro_splash.dart';

/// The Pro splash (docs/design/pro-open-animation.md), photographed at the
/// two frames that carry its meaning: « MyWeli Pro », and the mark it becomes.
///
/// A picture of an animation is a picture of an arbitrary frame unless the
/// frame is chosen (SYSTEM.md §20.1), so both are — and neither by guesswork:
///
///   · the **wordmark** is the still reduced motion holds through the intro
///     — the shipped behaviour, not a frame this test picked — and the test
///     asserts it sits inside the asset's `wordmark` hold before
///     photographing it (past the intro that still becomes the end frame);
///   · the **end frame** is the composition's last frame — the finished mark
///     the first pass and every spin come to rest on, and the frame the
///     screen leaves on (§2.2). It is reached by playing the pass through,
///     not by setting the controller: the shipped stop, photographed.
///
/// The session never resolves here, so the splash stays up to be photographed.
void main() {
  group('goldens', () {
    setUpAll(() async {
      await loadRealFonts();
      serviceLocator.authService = MockAuthService();
    });
    final timeline = OpenTimeline.pro();

    Future<void> pumpProSplash(WidgetTester tester) async {
      goldenSurface(tester);
      await tester.pumpWidget(
        ChangeNotifierProvider<ProAuthProvider>.value(
          value: FakeProSession(),
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: goldenTheme(),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('fr', 'FR')],
            locale: const Locale('fr', 'FR'),
            routerConfig: proSplashRouter(),
          ),
        ),
      );
      // `runAsync`, not more pumps: the composition is decoded off a real
      // bundle read, and a pump only flushes microtasks — without this the
      // golden would photograph an empty surface and call it the splash.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await pumpFirstFrame(tester);
    }

    AnimationController controllerOf(WidgetTester tester) =>
        tester.widget<LottieBuilder>(find.byType(LottieBuilder)).controller!
            as AnimationController;

    testWidgets('pro splash — « MyWeli Pro », the still reduced motion holds', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(
            disableAnimations: true,
            reduceMotion: true,
          );
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      await pumpProSplash(tester);
      await tester.pump(const Duration(milliseconds: 100));

      final (start, end) = timeline.wordmarkFrames;
      expect(
        timeline.frameOf(controllerOf(tester).value),
        inInclusiveRange(start, end),
        reason:
            'not the wordmark hold — this golden would photograph a fading '
            'letter, or the mark, and call it « MyWeli Pro »',
      );

      await expectGolden(tester, 'pro_splash_wordmark');
    });

    testWidgets('pro splash — the end frame: the finished mark', (
      tester,
    ) async {
      await pumpProSplash(tester);
      // The whole first pass plays out and stops on its end frame, where the
      // mark rests before the gate (the session never resolves here, so the
      // screen is still up to be photographed).
      await tester.pump(timeline.firstPass + OpenTimeline.frame);
      final controller = controllerOf(tester);

      expect(
        timeline.frameOf(controller.value),
        closeTo(timeline.endFrame, 0.01),
      );
      expect(controller.isAnimating, isFalse, reason: 'resting, not spinning');

      await expectGolden(tester, 'pro_splash_end');
    });
  }, skip: kGoldensSkip);
}

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
///   · the **end frame** is the composition's last frame, where the intro's
///     morph and every pass of the redraw loop come to rest.
///
/// The session never resolves here, so the splash stays up to be photographed.
void main() {
  group('goldens', () {
    setUpAll(() async {
      await loadRealFonts();
      serviceLocator.authService = MockAuthService();
    });
    final timeline = ProOpenTimeline.load();

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
      await tester.pump();
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
      // The intro plays out; the session is still pending, so the screen has
      // handed over to the redraw loop. Stop it on the frame every pass ends on.
      await tester.pump(timeline.intro);
      final controller = controllerOf(tester)
        ..stop()
        ..value = 1;
      await tester.pump();

      expect(
        timeline.frameOf(controller.value),
        closeTo(timeline.endFrame, 0.01),
      );

      await expectGolden(tester, 'pro_splash_end');
    });
  }, skip: kGoldensSkip);
}

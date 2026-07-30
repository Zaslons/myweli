import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/widgets/common/brand_loader.dart';

import '../support/golden.dart';

/// A8 — the loading state, finally photographable (SYSTEM.md §9.1, §20.1).
///
/// §20.1 has always listed `BrandLoader` under *"two things a golden cannot
/// pin"*, and for the animated cut that is still true: a picture of an
/// infinitely-repeating Lottie is a picture of an arbitrary frame. Under
/// reduced motion it holds a **still** frame by design, so exactly half of that
/// caveat is now retired — and the half that is retired is the one that changed
/// in this slice.
///
/// Both cuts are in frame because `fast` decides more than the asset: it is
/// what keeps the « Chargement… » caption out of a 24px list-footer row.
void main() {
  group('goldens', () {
    setUpAll(loadRealFonts);

    testWidgets('goldens the loader with motion off', (tester) async {
      // The shipped widget, with no `ReduceMotionObserver` above it — the
      // accessor's no-scope fallback is what `goldenApp` exercises, and that is
      // the honest thing to photograph: it is also what 100+ widget tests and
      // any un-wrapped root get.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(
            disableAnimations: true,
            reduceMotion: true,
          );
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      await pumpGolden(
        tester,
        const Padding(
          padding: EdgeInsets.all(AppTheme.spacingXL),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BrandLoader(),
              SizedBox(height: AppTheme.spacingXL),
              BrandLoader(size: AppTheme.iconM, fast: true),
            ],
          ),
        ),
        size: const Size(390, 260),
      );
      // **`runAsync`, not more pumps.** The composition is decoded off a real
      // bundle read, and `pump()` only flushes microtasks — the first version
      // of this golden pumped 400ms, loaded nothing, and photographed a caption
      // floating over an empty box. It passed. A wrong baseline is worse than
      // none (§20.1), and this one would have been a picture of the loader
      // NOT rendering, checked in as proof that it does.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await expectGolden(tester, 'components_loader_reduced_motion');
    });
  }, skip: kGoldensSkip);
}

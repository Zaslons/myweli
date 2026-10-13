import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/widgets/common/brand_loader.dart';
import 'package:myweli/widgets/common/timed_cached_image.dart';

import '../a11y/_a11y.dart';
import '../support/fonts.dart';
import '../support/pump_app.dart';

/// docs/design/pro-screenshot-shoot-fixes.md §2.3 — a slow image's timeout
/// state. It was a 25 % black scrim with a white « Réessayer » over the
/// still-spinning loader; in a third-width photo tile the label broke as
/// « Réessay / er ». Now: an opaque surface, the label only where it fits,
/// otherwise the icon with its tooltip.
void main() {
  // Widths are the point: the test font draws every glyph as a full square.
  setUpAll(loadRealFonts);

  Future<void> pumpTimedOut(
    WidgetTester tester, {
    required double width,
    required double height,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      wrapApp(
        theme: AppTheme.themeData(fontFamily: kRealFont),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 800),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: height,
                child: TimedCachedImage(
                  // Never answers under the test clock: the load stays
                  // pending, so the timer is what decides.
                  imageUrl: 'https://img.myweli.test/slow.jpg',
                  width: width,
                  height: height,
                  timeout: const Duration(seconds: 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
  }

  testWidgets('a narrow tile: the icon with the tooltip, no label', (
    tester,
  ) async {
    await pumpTimedOut(tester, width: 110, height: 110);
    expect(find.byTooltip('Réessayer'), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a roomy box: « Réessayer » spelled out', (tester) async {
    await pumpTimedOut(tester, width: 320, height: 180);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 2× text the label still fits the smallest roomy box whole', (
    tester,
  ) async {
    await pumpTimedOut(tester, width: 200, height: 72, scale: 2);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expectNoMidWordBreak(tester, 'Réessayer', '200×72 at 2×');
  });

  testWidgets('the cover is opaque and in tokens — no loader shows through', (
    tester,
  ) async {
    await pumpTimedOut(tester, width: 110, height: 110);
    // The loader is still in the tree (the request is alive) but under an
    // opaque `surface` cover drawn after it.
    // The cover, not the loading placeholder (also `surface`): the one in the
    // Positioned.fill over the image.
    final cover = find.descendant(
      of: find.byType(Positioned),
      matching: find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == AppColors.surface,
      ),
    );
    expect(cover, findsOneWidget);
    expect(AppColors.surface.a, 1.0, reason: 'the cover must be opaque');
    // The loader is really there — else the next check is vacuous …
    final loader = find.byType(BrandLoader);
    expect(loader, findsOneWidget);
    // … and the cover is ON it: a touch at the loader's centre reaches the
    // cover first (a Stack hit-tests its children in paint order, top down),
    // so a cover painted under the loader cannot pass.
    final hits = tester.hitTestOnBinding(tester.getCenter(loader)).path;
    expect(
      hits.any((e) => e.target == tester.renderObject(cover)),
      isTrue,
      reason: 'the cover is above the loader',
    );
    // No scrim of literal black.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.color != null &&
            w.color!.a < 1 &&
            w.color!.r == 0 &&
            w.color!.g == 0 &&
            w.color!.b == 0,
      ),
      findsNothing,
    );
  });
}

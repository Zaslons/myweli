import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/formatters.dart';
import 'package:myweli/widgets/common/app_chip.dart';
import 'package:myweli/widgets/common/app_rating.dart';

import '../support/pump_app.dart';

/// docs/design/salon-rating-new-and-visits-card.md §2.1 — one rating rule for
/// every salon site: a French numeral when there are reviews, « Nouveau » when
/// there are none. Every site used to print « ★ 0.0 · 0 avis ».
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double scale = 1,
    double width = 360,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrapApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [child],
            ),
          ),
        ),
      ),
    );
  }

  group('Formatters.formatRating', () {
    test('French decimal comma, one decimal', () {
      expect(Formatters.formatRating(4.8), '4,8');
      expect(Formatters.formatRating(5), '5,0');
      expect(Formatters.formatRating(4.86), '4,9');
    });
  });

  testWidgets('with reviews: « ★ 4,8 (32 avis) », never « 4.8 »', (
    tester,
  ) async {
    await pump(tester, const AppRating(rating: 4.8, reviewCount: 32));
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.text('4,8'), findsOneWidget);
    expect(find.text('(32 avis)'), findsOneWidget);
    expect(find.text('4.8'), findsNothing);
    expect(find.text('Nouveau'), findsNothing);
    expect(find.bySemanticsLabel('Note 4,8 sur 5, 32 avis'), findsOneWidget);
  });

  testWidgets('compact (cards, map sheet): « ★ 4,8 (32) »', (tester) async {
    await pump(
      tester,
      const AppRating(
        rating: 4.8,
        reviewCount: 32,
        size: AppRatingSize.compact,
      ),
    );
    expect(find.text('4,8'), findsOneWidget);
    expect(find.text('(32)'), findsOneWidget);
  });

  testWidgets('large (« Avis » summary): « 4,8 » over « 32 avis »', (
    tester,
  ) async {
    await pump(
      tester,
      const AppRating(rating: 4.8, reviewCount: 32, size: AppRatingSize.large),
    );
    expect(find.text('4,8'), findsOneWidget);
    expect(find.text('32 avis'), findsOneWidget);
  });

  for (final size in AppRatingSize.values) {
    testWidgets('no review → « Nouveau », no star, no 0,0 ($size)', (
      tester,
    ) async {
      await pump(tester, AppRating(rating: 0, reviewCount: 0, size: size));
      expect(find.text('Nouveau'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.textContaining('0,0'), findsNothing);
      expect(find.textContaining('0.0'), findsNothing);
      expect(find.textContaining('avis'), findsNothing);
      expect(
        find.bySemanticsLabel('Nouveau salon, pas encore d’avis'),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'the pill is exactly as tall as the rating row it replaces (16 at 1×) and '
    'is not stretched by a `stretch` parent',
    (tester) async {
      await pump(tester, const AppRating(rating: 0, reviewCount: 0));
      // `AppChip.status(dense: true)` since B9.8 F3.
      final pill = find.ancestor(
        of: find.text('Nouveau'),
        matching: find.byType(AppChip),
      );
      final size = tester.getSize(pill.first);
      // `ProviderCard._textBlockHeight` budgets the rating row at 16.
      expect(size.height, 16);
      expect(size.width, lessThan(120), reason: 'a pill, not a full-width bar');

      await pump(tester, const AppRating(rating: 4.8, reviewCount: 32));
      expect(tester.getSize(find.byType(AppRating)).height, 16);
    },
  );

  for (final size in AppRatingSize.values) {
    testWidgets('360dp at 200% text: no overflow ($size)', (tester) async {
      await pump(
        tester,
        AppRating(rating: 4.8, reviewCount: 1234, size: size),
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      await pump(
        tester,
        AppRating(rating: 0, reviewCount: 0, size: size),
        scale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

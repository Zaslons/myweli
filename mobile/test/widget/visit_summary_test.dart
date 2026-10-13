import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/utils/formatters.dart';
import 'package:myweli/widgets/booking/visit_summary.dart';

import '../a11y/_a11y.dart';
import '../support/fonts.dart';

/// docs/design/amounts-that-fit.md §2 — the consumer's « Mes rendez-vous →
/// Historique » summary: two tiles across, or one per row when the amount
/// would not fit half the width. They were two `Expanded`s in a plain `Row`:
/// a long total broke inside its number, and a tile whose value wrapped stood
/// taller than its neighbour.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    await loadRealFonts();
  });

  /// As on the screen: 16dp of page padding either side.
  Future<void> pump(
    WidgetTester tester, {
    required double width,
    required double scale,
    required double spent,
    int visits = 12,
  }) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(fontFamily: kRealFont),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            children: [VisitSummary(visits: visits, spent: spent)],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The tile's inner width with [n] tiles per row: 16dp page padding each
  /// side, a 16dp gap, 16dp tile padding each side.
  double inner(double width, int n) => (width - 32 - (n - 1) * 16) / n - 32;

  Rect tileOf(WidgetTester tester, String label) => tester.getRect(
    find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
  );

  for (final spent in [0.0, 75000.0, 1250000.0, 123456789.0]) {
    for (final width in [360.0, 393.0, 430.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        final amount = Formatters.formatCurrency(spent);
        testWidgets('« $amount » at ${width.toInt()}dp × $scale×', (
          tester,
        ) async {
          await pump(tester, width: width, scale: scale, spent: spent);
          expect(tester.takeException(), isNull);
          final at = '${width.toInt()}dp × $scale×';

          // 1. The amount is whole.
          expectNoMidWordBreak(tester, amount, '« $amount » at $at');

          // 2. The shape, read off the screen.
          final count = tileOf(tester, 'visites');
          final money = tileOf(tester, 'dépensés');
          final across = count.top < money.bottom && money.top < count.bottom
              ? 2
              : 1;
          expect(count.width, closeTo(inner(width, across) + 32, 0.5));
          if (across == 2) {
            expect(money.height, closeTo(count.height, 0.5));
            expect(money.top, closeTo(count.top, 0.5));
          }

          // 3. It is the widest shape that fits.
          if (across == 1) {
            final p = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.text(amount),
                matching: find.byType(RichText),
              ),
            );
            var widest = 0.0;
            for (final token in unbreakableTokens(amount)) {
              final tp = TextPainter(
                text: TextSpan(text: token, style: p.text.style),
                textDirection: TextDirection.ltr,
                textScaler: p.textScaler,
              )..layout();
              if (tp.width > widest) widest = tp.width;
              tp.dispose();
            }
            expect(
              widest,
              greaterThan(inner(width, 2)),
              reason:
                  'one per row at $at, yet « $amount » '
                  '(${widest.toStringAsFixed(1)}dp) would fit two across '
                  '(${inner(width, 2).toStringAsFixed(1)}dp)',
            );
          }
        });
      }
    }
  }

  testWidgets('one visit reads « visite »', (tester) async {
    await pump(tester, width: 360, scale: 1, spent: 15000, visits: 1);
    expect(find.text('visite'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });
}

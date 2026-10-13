import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/text_styles.dart';
import 'package:myweli/core/utils/text_fit.dart';

import '../support/fonts.dart';

/// docs/design/amounts-that-fit.md §5 — the measure a layout decides by.
///
/// It is a second copy of what `Text.build` does to a style, so its first
/// duty is to AGREE with `Text`: the tests below draw a string and compare
/// the paragraph's width with the measure, under every condition `Text`
/// reads from the context.
void main() {
  setUpAll(loadRealFonts);

  const nnbsp = ' ';

  group('tokens — what the engine may not break', () {
    test('a grouped number is one token, its unit another', () {
      expect(TextFit.tokens('180${nnbsp}000 FCFA'), ['180${nnbsp}000', 'FCFA']);
      expect(TextFit.tokens('1${nnbsp}250${nnbsp}000 FCFA'), [
        '1${nnbsp}250${nnbsp}000',
        'FCFA',
      ]);
    });

    test('a range breaks around its dash, never inside an amount', () {
      expect(TextFit.tokens('15${nnbsp}000 – 25${nnbsp}000 FCFA'), [
        '15${nnbsp}000',
        '–',
        '25${nnbsp}000',
        'FCFA',
      ]);
    });

    test('a hyphen between letters is a legal break; between digits not', () {
      expect(TextFit.tokens('Rendez-vous'), ['Rendez-', 'vous']);
      expect(TextFit.tokens('2026-10-13'), ['2026-10-13']);
      expect(TextFit.tokens('-5${nnbsp}000 FCFA'), ['-5${nnbsp}000', 'FCFA']);
    });

    test('glue left at the end of a token is not part of it', () {
      expect(TextFit.tokens('180${nnbsp}000  FCFA'), [
        '180${nnbsp}000',
        'FCFA',
      ]);
    });

    test('words, dates and phone pairs split at their spaces', () {
      expect(TextFit.tokens('13 oct. 2026'), ['13', 'oct.', '2026']);
      expect(TextFit.tokens('+225 07 00 00 01 01'), [
        '+225',
        '07',
        '00',
        '00',
        '01',
        '01',
      ]);
      expect(TextFit.tokens('  '), isEmpty);
    });
  });

  /// Pumps [text] under [media], and hands back the width `Text` drew it at
  /// and the width [TextFit] measures from the same context.
  Future<({double drawn, double measured})> drawAndMeasure(
    WidgetTester tester,
    String text,
    TextStyle style, {
    MediaQueryData Function(MediaQueryData)? media,
  }) async {
    late TextFit fit;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(fontFamily: kRealFont),
        builder: (context, child) => MediaQuery(
          data: (media ?? (m) => m)(MediaQuery.of(context)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              fit = TextFit.of(context);
              // A Row gives its child an unbounded width: one line, as wide
              // as the text is.
              return Row(children: [Text(text, style: style)]);
            },
          ),
        ),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    );
    return (drawn: paragraph.size.width, measured: fit.lineWidth(text, style));
  }

  group('the measure is what Text draws', () {
    const amount = '180${nnbsp}000';

    testWidgets('a style that names no font — the theme supplies it', (
      tester,
    ) async {
      final r = await drawAndMeasure(tester, amount, AppTextStyles.titleMedium);
      expect(r.measured, closeTo(r.drawn, 0.01));
      // …and it is the real face, not the test placeholder (every glyph a
      // square of the font size would make this 112dp).
      expect(r.drawn, closeTo(58.9, 0.5));
    });

    testWidgets('at a larger text size', (tester) async {
      final r = await drawAndMeasure(
        tester,
        amount,
        AppTextStyles.titleMedium,
        media: (m) => m.copyWith(textScaler: const TextScaler.linear(1.3)),
      );
      expect(r.measured, closeTo(r.drawn, 0.01));
      expect(r.drawn, greaterThan(70));
    });

    testWidgets('with OS bold text', (tester) async {
      final plain = await drawAndMeasure(
        tester,
        amount,
        AppTextStyles.bodyMedium,
      );
      final bold = await drawAndMeasure(
        tester,
        amount,
        AppTextStyles.bodyMedium,
        media: (m) => m.copyWith(boldText: true),
      );
      expect(bold.measured, closeTo(bold.drawn, 0.01));
      expect(bold.drawn, greaterThan(plain.drawn), reason: 'bold is wider');
    });

    testWidgets('with a letter-spacing override', (tester) async {
      final plain = await drawAndMeasure(
        tester,
        amount,
        AppTextStyles.titleMedium,
      );
      final spaced = await drawAndMeasure(
        tester,
        amount,
        AppTextStyles.titleMedium,
        media: (m) => m.applyTextStyleOverrides(
          lineHeightScaleFactorOverride: null,
          letterSpacingOverride: 2,
          wordSpacingOverride: null,
          paragraphSpacingOverride: null,
        ),
      );
      expect(spaced.measured, closeTo(spaced.drawn, 0.01));
      expect(spaced.drawn, greaterThan(plain.drawn + 5));
    });
  });

  group('holds / columns', () {
    Future<TextFit> fitOf(WidgetTester tester) async {
      late TextFit fit;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.themeData(fontFamily: kRealFont),
          // A Scaffold, as on every real screen: it is what puts the themed
          // DefaultTextStyle (and so the font) above the measure. Without it
          // the fallback style applies and « 180 000 » measures another face.
          home: Scaffold(
            body: Builder(
              builder: (context) {
                fit = TextFit.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return fit;
    }

    const price = (
      text: '180${nnbsp}000 FCFA',
      style: AppTextStyles.titleMedium,
    );

    testWidgets('a box holds an amount when its NUMBER fits, unit apart', (
      tester,
    ) async {
      final fit = await fitOf(tester);
      // « 180 000 » is 58.9dp; the whole « 180 000 FCFA » would be ~100.
      expect(fit.holds(60, [price]), isTrue);
      expect(fit.holds(56, [price]), isFalse);
    });

    testWidgets('on the edge, the narrower shape wins', (tester) async {
      final fit = await fitOf(tester);
      final exact = fit.widestToken(price.text, price.style);
      expect(fit.holds(exact, [price]), isFalse);
      expect(fit.holds(exact + TextFit.slack, [price]), isTrue);
    });

    testWidgets('columns: the first candidate that holds every text', (
      tester,
    ) async {
      final fit = await fitOf(tester);
      int pick(double width) => fit.columns(
        candidates: const [4, 2, 1],
        cellWidth: (n) => width / n,
        texts: [price, (text: 'Absences', style: AppTextStyles.labelSmall)],
      );
      expect(pick(400), 4); // 100dp cells
      expect(pick(200), 2); // 50dp cells are too narrow, 100dp are not
      expect(pick(100), 1);
      expect(pick(40), 1, reason: 'nothing wider is left to give');
    });
  });
}

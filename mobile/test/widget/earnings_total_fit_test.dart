import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/text_styles.dart';
import 'package:myweli/core/utils/formatters.dart';
import 'package:myweli/screens/provider/earnings/earnings_screen.dart';

import '../a11y/_a11y.dart';
import '../support/fonts.dart';
import '../support/pump_app.dart';

/// docs/design/pro-app-batch7.md §10 (B7.10, the owner's decision of
/// 2026-10-22) — the « Total réalisé » figure takes the largest headline
/// size in which it stays whole: unchanged at the default size, a step down
/// only when the number would break. Held here both ways, because the layout
/// gate alone would also pass a total that ALWAYS shrank.
void main() {
  setUpAll(loadRealFonts);

  Future<double?> sizeAt(WidgetTester tester, num amount, double scale) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final figure = Formatters.formatCurrency(amount.toDouble());
    await pumpApp(
      tester,
      theme: AppTheme.themeData(fontFamily: kRealFont),
      // The card's width on a 360 dp phone: 16 dp margin, 24 dp padding.
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingM + AppTheme.spacingL),
          child: EarningsTotal(figure),
        ),
      ),
    );
    expectNoMidWordBreak(tester, figure, 'the total');
    return tester.widget<Text>(find.text(figure)).style?.fontSize;
  }

  testWidgets('the default size: headlineLarge, even at seven digits', (
    tester,
  ) async {
    expect(
      await sizeAt(tester, 1250000, 1),
      AppTextStyles.headlineLarge.fontSize,
    );
  });

  testWidgets('at 200 %, a small total keeps headlineLarge', (tester) async {
    expect(
      await sizeAt(tester, 45000, 2),
      AppTextStyles.headlineLarge.fontSize,
    );
  });

  // Eight digits, not seven: « 1 250 000 » at 64 px measured 283 dp on a Mac
  // against the 280 dp box — 3 dp over, decided by the width of the U+202F
  // glue, which Linux measures narrower (this case was red on the Mac and
  // green in CI). Eight digits alone are 294 dp, whatever the glue: too wide
  // for headlineLarge on every platform. The widget itself measures on the
  // device, so it is right either way; only the test's case was borderline.
  testWidgets('at 200 %, a figure headlineLarge cannot hold (eight digits) '
      'steps down — and stays whole', (tester) async {
    expect(
      await sizeAt(tester, 12500000, 2),
      lessThan(AppTextStyles.headlineLarge.fontSize!),
    );
  });
}

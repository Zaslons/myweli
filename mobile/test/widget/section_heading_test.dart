import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/text_styles.dart';
import 'package:myweli/widgets/common/section_heading.dart';

import '../support/fonts.dart';
import '../support/pump_app.dart';
import '../support/surface.dart';

/// `SectionHeading` is the same height whether or not it is tappable (A11 C8).
///
/// ## Why this exists, and why a golden did not catch it
///
/// C5 extracted this widget from `_SectionCard`, and the extraction lost
/// something. The original applied
/// `Container(padding: EdgeInsets.symmetric(vertical: spacingXS))`
/// **unconditionally**, *outside* its `InkWell`. The extraction moved that
/// padding **inside** the `onTap != null` branch.
///
/// Only 1 of the 7 salon-detail sections passes a tap handler, so six headings
/// — Vos rendez-vous ici, Contact, Photos, Avant/Après, Avis, À propos — lost
/// 8dp of vertical space and moved 4dp closer to their content.
///
/// **`consumer_provider_detail.png` was regenerated in the same commit.** So
/// the picture that exists to catch a visual regression recorded this one as
/// the new truth instead — §20.1's named failure mode, and the reason the
/// adversarial review runs *after* the suite is green rather than before.
void main() {
  setUpAll(loadRealFonts);

  Future<double> heightOf(WidgetTester tester, {VoidCallback? onTap}) async {
    pinSurface(tester, size: const Size(360, 800));
    await pumpApp(
      tester,
      theme: AppTheme.themeData(fontFamily: kRealFont),
      home: Scaffold(
        body: SectionHeading(
          title: 'Contact',
          style: AppTextStyles.titleMedium,
          onTap: onTap,
        ),
      ),
    );
    await tester.pump();
    return tester.getSize(find.byType(SectionHeading)).height;
  }

  testWidgets('an untappable heading keeps its vertical padding', (
    tester,
  ) async {
    final bare = await heightOf(tester);

    // The text alone, in the same style and on the same surface — so the
    // comparison is "the heading is padded", not a guess at a pixel count.
    final textHeight = tester
        .getSize(
          find.descendant(
            of: find.byType(SectionHeading),
            matching: find.byType(Text),
          ),
        )
        .height;

    expect(
      bare,
      closeTo(textHeight + 2 * AppTheme.spacingXS, 0.51),
      reason:
          'the heading is ${bare}dp tall around ${textHeight}dp of text, '
          'so it carries ${bare - textHeight}dp of padding instead of '
          '${2 * AppTheme.spacingXS}. Six salon-detail sections are untappable '
          'and this is the only thing holding them off their content.',
    );
  });

  testWidgets('the tappable one still meets the 48dp target (§13.2)', (
    tester,
  ) async {
    expect(
      await heightOf(tester, onTap: () {}),
      greaterThanOrEqualTo(48.0),
      reason: 'a tappable heading is a control, and §13.2 has a floor',
    );
  });
}

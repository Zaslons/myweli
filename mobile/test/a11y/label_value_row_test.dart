import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/text_styles.dart';
import 'package:myweli/widgets/common/label_value_row.dart';

import '../support/fonts.dart';
import '_a11y.dart';

/// The money rows, at the floor (A12).
///
/// The shape §21 row 68 names three times and a sweep found **twenty** of:
/// `Row(spaceBetween, [Text(label), Text(value)])` with neither child flexed,
/// so `RenderFlex` hands each its full intrinsic width and the row runs off the
/// screen rather than either side giving way.
///
/// ## What this file actually gates, and what it does not
///
/// **Corrected after the adversarial review**, which is the only reason it is
/// stated honestly. The first version of this docstring said the component test
/// was all that was available because "two of them need a booking in progress
/// to reach" — false, and the cost of the wrong excuse was a live 81px overflow
/// on the booking-confirmation screen. Both booking screens and the notification
/// centre are `layout_test.dart` subjects now; **that** is where the wiring is
/// proven.
///
/// And of the six assertions per case, exactly one can fail. `LabelValueRow` is
/// a `Wrap` of two plain `Text`s — no `maxLines`, no `overflow`, no flex — and
/// `RenderWrap` gives a horizontal child `maxWidth: constraints.maxWidth` with
/// **unbounded height**. So `expectNoUndeclaredTruncation`, `expectNoLegibilityCrush`
/// and `expectNoVerticalClip` are structurally incapable of firing here, the two
/// `find.text` guards match the strings the test itself passed in, and
/// `expectNoMidWordBreak`'s worst case clears by 62%. They are kept because they
/// cost nothing and would catch a future change of shape; they are **not** what
/// makes this file worth running.
///
/// `tester.takeException()` is. An unflexed `Row` of « Acompte (30%) » +
/// « 7 500 FCFA » at 2× overflows, and that is the regression this file exists
/// to hold — so read a green run as "the Wrap is still a Wrap", not as "seven
/// properties verified".
void main() {
  setUpAll(loadRealFonts);

  /// Every label/value pair `LabelValueRow` renders in `lib/`, with the styles
  /// its call site passes. Tabled rather than invented — the shape
  /// `app_button_test.dart` uses for every `actionText`.
  ///
  /// It claimed to be every pair while listing 7 of 10; it is now all **11**,
  /// across the six files that use the widget. And the money values carry
  /// U+202F, the narrow no-break space `NumberFormat(fr_FR)` actually emits —
  /// the first version used a plain U+0020, so it measured a string the product
  /// never renders.
  final pairs =
      <String, ({String label, String value, TextStyle? l, TextStyle? v})>{
    // booking confirmation — the screen immediately before payment
    'Total (range)': (
      label: 'Total',
      value: 'À partir de 25 000 FCFA',
      l: AppTextStyles.bodyMedium,
      v: null,
    ),
    'Acompte': (
      label: 'Acompte (30%)',
      value: '7 500 FCFA',
      l: AppTextStyles.titleMedium,
      v: AppTextStyles.titleLarge,
    ),
    'Solde': (
      label: 'Solde à régler au salon',
      value: '17 500 FCFA',
      l: AppTextStyles.bodySmall,
      v: null,
    ),
    // the booking hub's pinned summary bar
    'hub Total': (
      label: 'Total',
      value: '25 000 FCFA',
      l: AppTextStyles.titleMedium,
      v: AppTextStyles.titleLarge,
    ),
    // deposit settings — the worst of the set at ~150dp over
    'Acompte payé en ligne': (
      label: 'Acompte payé en ligne',
      value: '6 000 FCFA',
      l: null,
      v: AppTextStyles.bodyMedium,
    ),
    'Pourcentage': (
      label: 'Pourcentage de l’acompte',
      value: '30 %',
      l: null,
      v: AppTextStyles.titleMedium,
    ),
    'Solde au salon': (
      label: 'Solde au salon',
      value: '14 000 FCFA',
      l: AppTextStyles.bodySmall,
      v: null,
    ),
    // The four the first table missed.
    'confirmation service': (
      label: 'Tissage',
      value: 'À partir de 15 000 FCFA',
      l: AppTextStyles.bodyMedium,
      v: AppTextStyles.bodyMedium,
    ),
    'manual booking Total': (
      label: 'Total',
      value: '25 000 FCFA',
      l: AppTextStyles.bodyMedium,
      v: AppTextStyles.titleMedium,
    ),
    'export count': (
      label: 'Rendez-vous',
      value: '128',
      l: null,
      v: AppTextStyles.bodyMedium,
    ),
    'appointment card Total:': (
      label: 'Total:',
      value: '15 000 FCFA',
      l: AppTextStyles.bodyMedium,
      v: AppTextStyles.titleMedium,
    ),
  };

  for (final width in [360.0, 375.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      final at = '${width.toInt()}dp × ${scale.toInt()}× text';
      for (final e in pairs.entries) {
        testWidgets('« ${e.key} » fits $at', (tester) async {
          await pumpAtWidth(
            tester,
            width: width,
            scale: scale,
            // The narrowest real host: screen padding 16 + card padding 24,
            // i.e. the booking-confirmation summary card, which is where the
            // worst of these live.
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(40),
                child: LabelValueRow(
                  label: e.value.label,
                  value: e.value.value,
                  labelStyle: e.value.l,
                  valueStyle: e.value.v,
                ),
              ),
            ),
          );

          expect(find.text(e.value.label), findsOneWidget, reason: 'C');
          expect(find.text(e.value.value), findsOneWidget, reason: 'C');
          expect(tester.takeException(), isNull, reason: 'A: $at');
          expectNoUndeclaredTruncation(tester, context: at);
          expectNoLegibilityCrush(tester, context: at);
          expectNoVerticalClip(tester, context: at);
          // A price is a value the user reads as ONE token (§13.3).
          expectNoMidWordBreak(tester, e.value.value, at);
        });
      }
    }
  }
}

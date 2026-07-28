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
/// Gated here as a COMPONENT rather than on its screens, and the reason is
/// worth stating: none of the three — booking confirmation, the booking hub's
/// pinned bar, deposit settings — is a width-gate subject, and two of them need
/// a booking in progress to reach. A component test with the **real pairs** is
/// what is available today; making those screens subjects is the honest
/// follow-up, and until then this proves the widget and not the wiring.
void main() {
  setUpAll(loadRealFonts);

  /// Every label/value pair `LabelValueRow` now renders in `lib/`, with the
  /// styles its call site passes. Tabled rather than invented — the shape
  /// `app_button_test.dart` uses for every `actionText`.
  final pairs =
      <String, ({String label, String value, TextStyle? l, TextStyle? v})>{
    // booking confirmation — the screen immediately before payment
    'Total (range)': (
      label: 'Total',
      value: 'À partir de 25 000 FCFA',
      l: AppTextStyles.bodyMedium,
      v: null,
    ),
    'Acompte': (
      label: 'Acompte (30%)',
      value: '7 500 FCFA',
      l: AppTextStyles.titleMedium,
      v: AppTextStyles.titleLarge,
    ),
    'Solde': (
      label: 'Solde à régler au salon',
      value: '17 500 FCFA',
      l: AppTextStyles.bodySmall,
      v: null,
    ),
    // the booking hub's pinned summary bar
    'hub Total': (
      label: 'Total',
      value: '25 000 FCFA',
      l: AppTextStyles.titleMedium,
      v: AppTextStyles.titleLarge,
    ),
    // deposit settings — the worst of the set at ~150dp over
    'Acompte payé en ligne': (
      label: 'Acompte payé en ligne',
      value: '6 000 FCFA',
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
      value: '14 000 FCFA',
      l: AppTextStyles.bodySmall,
      v: null,
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

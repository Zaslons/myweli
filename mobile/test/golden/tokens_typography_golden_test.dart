import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/core/theme/text_styles.dart';

import '../support/golden.dart';

/// The whole type scale, rendered in French (docs/design/SYSTEM.md §4).
///
/// Every style here is pulled from `AppTextStyles` and gets its typeface from
/// the THEME — so this sheet is also the proof that the `fontFamily` seam
/// reaches the styles a screen actually uses, not just the ones it hardcodes.
///
/// Watch here for: the ink change (A1), and A2 raising the six 10px sites to the
/// 11px floor — `labelSmall` is the smallest text the product is allowed to use.
void main() {
  group('goldens', () {
    setUpAll(loadGoldenFonts);

    testWidgets('the type scale', (tester) async {
      await pumpGolden(
        tester,
        const _TypeSheet(),
        size: const Size(470, 700),
      );
      await expectGolden(tester, 'tokens_typography');
    });

    testWidgets('the three text tiers, at the same size', (tester) async {
      await pumpGolden(
        tester,
        const _TiersSheet(),
        size: const Size(470, 330),
      );
      await expectGolden(tester, 'tokens_text_tiers');
    });
  }, skip: kGoldensSkip);
}

const _samples = <(String, TextStyle, String)>[
  ('headlineLarge', AppTextStyles.headlineLarge, '32 · w600'),
  ('headlineMedium', AppTextStyles.headlineMedium, '28 · w600'),
  ('headlineSmall', AppTextStyles.headlineSmall, '24 · w600'),
  ('titleLarge', AppTextStyles.titleLarge, '22 · w600'),
  ('titleMedium', AppTextStyles.titleMedium, '16 · w500'),
  ('titleSmall', AppTextStyles.titleSmall, '14 · w500'),
  ('bodyLarge', AppTextStyles.bodyLarge, '16 · w400'),
  ('bodyMedium', AppTextStyles.bodyMedium, '14 · w400'),
  ('bodySmall', AppTextStyles.bodySmall, '12 · w400'),
  ('labelLarge', AppTextStyles.labelLarge, '14 · w500'),
  ('labelMedium', AppTextStyles.labelMedium, '12 · w500'),
  ('labelSmall', AppTextStyles.labelSmall, '11 · w500 — the floor'),
];

class _TypeSheet extends StatelessWidget {
  const _TypeSheet();

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.background,
        padding: const EdgeInsets.all(AppTheme.spacingM),
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final (name, style, spec) in _samples)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.spacingM),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$name  ·  $spec', style: _meta),
                    const SizedBox(height: 2),
                    // A real French string: accents, and the ~20% expansion the
                    // layout has to survive (SYSTEM.md §17).
                    Text('Réservez chez Beauté Divine', style: style),
                  ],
                ),
              ),
          ],
        ),
      );
}

/// The same sentence in all three legal text colors — the clearest possible
/// before/after for A1's ink change and the `textTertiary` fix.
class _TiersSheet extends StatelessWidget {
  const _TiersSheet();

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.background,
        padding: const EdgeInsets.all(AppTheme.spacingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (name, color) in const [
              ('textPrimary', AppColors.textPrimary),
              ('textSecondary', AppColors.textSecondary),
              ('textTertiary', AppColors.textTertiary),
              ('textDisabled', AppColors.textDisabled),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.spacingM),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: _meta),
                    Text(
                      'Votre rendez-vous est confirmé à 14:30.',
                      style: AppTextStyles.bodyLarge.copyWith(color: color),
                    ),
                    Text(
                      'Votre rendez-vous est confirmé à 14:30.',
                      style: AppTextStyles.labelSmall.copyWith(color: color),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

const _meta = TextStyle(
  fontFamily: kGoldenFont,
  fontSize: 10,
  fontWeight: FontWeight.w500,
  letterSpacing: 0.8,
  color: AppColors.textTertiary,
);

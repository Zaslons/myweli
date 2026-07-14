import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/core/theme/text_styles.dart';
import 'package:myweli/screens/admin/widgets/status_chip.dart';
import 'package:myweli/widgets/common/empty_state.dart';

import '../support/golden.dart';

/// Status, chips, cards and the rating (docs/design/SYSTEM.md §3.5, §11, §12).
///
/// The rating row is the point of §3.5: **meaning never rides on hue.** The star
/// is `starRating` at 1.62:1 — invisible to a low-vision user and meaningless to
/// a colour-blind one — so the NUMBER carries the information and the star is
/// decoration. Read this sheet in greyscale: nothing should be lost.
void main() {
  group('goldens', () {
    setUpAll(loadGoldenFonts);

    testWidgets('status, chips, cards, rating', (tester) async {
      await pumpGolden(
        tester,
        const _FeedbackSheet(),
        size: const Size(390, 700),
      );
      await expectGolden(tester, 'components_feedback');
    });

    testWidgets('the empty state', (tester) async {
      await pumpGolden(
        tester,
        const EmptyState(
          icon: Icons.calendar_today_outlined,
          title: 'Aucun rendez-vous',
          description:
              'Vos réservations à venir apparaîtront ici. Trouvez un salon '
              'et réservez en quelques secondes.',
          actionText: 'Découvrir les salons',
          onAction: _noop,
        ),
      );
      await expectGolden(tester, 'components_empty_state');
    });
  }, skip: kGoldensSkip);
}

class _FeedbackSheet extends StatelessWidget {
  const _FeedbackSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(AppTheme.spacingM),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const GoldenSection(
            title: 'StatusChip — kind, never colour, is the API',
            child: Wrap(
              spacing: AppTheme.spacingS,
              runSpacing: AppTheme.spacingS,
              children: [
                StatusChip(label: 'confirmé', kind: AdminChipKind.ok),
                StatusChip(label: 'en attente', kind: AdminChipKind.pending),
                StatusChip(label: 'annulé', kind: AdminChipKind.danger),
                StatusChip(label: 'brouillon', kind: AdminChipKind.neutral),
              ],
            ),
          ),
          const GoldenSection(
            title: 'Rating — the glyph decorates, the NUMBER informs (§3.5)',
            child: _Rating(),
          ),
          GoldenSection(
            title: 'Card — secondary on background, no border, no shadow',
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingM),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Beauté Divine', style: AppTextStyles.titleMedium),
                    const SizedBox(height: AppTheme.spacingXS),
                    Text(
                      'Cocody · Coiffure & Tresses',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingS),
                    const Divider(),
                    const SizedBox(height: AppTheme.spacingS),
                    Text(
                      'À partir de 15 000 FCFA',
                      style: AppTextStyles.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const GoldenSection(
            title: 'Chips',
            child: Wrap(
              spacing: AppTheme.spacingS,
              children: [
                Chip(label: Text('Coiffure')),
                Chip(label: Text('Spa')),
                FilterChip(
                  label: Text('À domicile'),
                  selected: true,
                  onSelected: _noopBool,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Rating extends StatelessWidget {
  const _Rating();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Icon(Icons.star, size: 20, color: AppColors.starRating),
          const SizedBox(width: AppTheme.spacingXS),
          Text('4,8', style: AppTextStyles.titleMedium),
          const SizedBox(width: AppTheme.spacingXS),
          Text(
            '(32 avis)',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(width: AppTheme.spacingL),
          // The interactive star input: state by GLYPH (outline → filled), so it
          // still reads with the colour removed.
          for (var i = 0; i < 5; i++)
            Icon(
              i < 4 ? Icons.star : Icons.star_border,
              size: 20,
              color: AppColors.starRating,
            ),
        ],
      );
}

void _noop() {}
void _noopBool(bool _) {}

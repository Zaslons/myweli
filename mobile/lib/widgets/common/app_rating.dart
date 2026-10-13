import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';

/// How much of the rating a site has room for.
enum AppRatingSize {
  /// Cards and the map sheet: `★ 4,8 (32)`.
  compact,

  /// The salon header: `★ 4,8 (32 avis)`.
  regular,

  /// The « Avis » summary: a large `★ 4,8` over `32 avis`.
  large,
}

/// The shared salon rating (SYSTEM.md §3.5, §11.3) — the app twin of the
/// web's `Rating`. One rule everywhere
/// (docs/design/salon-rating-new-and-visits-card.md):
///
/// - at least one review → glyph + French numeral, `★ 4,8 (32 avis)`; the
///   star is decoration, the numeral is the information (§3.5);
/// - no review → a quiet « Nouveau » pill. Every site used to print
///   « ★ 0.0 · 0 avis », so a new salon — every salon at launch — read as a
///   one-star failure.
class AppRating extends StatelessWidget {
  const AppRating({
    super.key,
    required this.rating,
    required this.reviewCount,
    this.size = AppRatingSize.regular,
  });

  final double rating;
  final int reviewCount;
  final AppRatingSize size;

  /// What a screen reader says, and what the « Nouveau » pill stands for.
  String get semanticsLabel => reviewCount == 0
      ? 'Nouveau salon, pas encore d’avis'
      : 'Note ${Formatters.formatRating(rating)} sur 5, $reviewCount avis';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      // The label replaces the parts — otherwise « étoile, 4,8, (32) » is read.
      excludeSemantics: true,
      // The pill sits in a min-width Row like the rated form, so a parent
      // Column with `stretch` cannot widen it into a full-width bar.
      child: reviewCount == 0
          ? const Row(mainAxisSize: MainAxisSize.min, children: [_NewPill()])
          : _rated(),
    );
  }

  Widget _rated() {
    final value = Formatters.formatRating(rating);
    switch (size) {
      case AppRatingSize.large:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.star,
              size: AppTheme.iconL,
              color: AppColors.starRating,
            ),
            const SizedBox(width: AppTheme.spacingSM),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTextStyles.titleLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '$reviewCount avis',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        );
      case AppRatingSize.regular:
      case AppRatingSize.compact:
        final count = size == AppRatingSize.compact
            ? '($reviewCount)'
            : '($reviewCount avis)';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.star,
              size: AppTheme.iconXS,
              color: AppColors.starRating,
            ),
            const SizedBox(width: AppTheme.spacingXS),
            Text(
              value,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: AppTheme.spacingS),
            Flexible(
              child: Text(
                count,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        );
    }
  }
}

/// « Nouveau » — the journal's badge idiom (label colour at 10 % fill) in a
/// pill, like the web's `ink` `Chip` (`web/components/Rating.tsx`). It
/// describes the salon; it is not a status, so it takes the ink, not a
/// semantic colour.
class _NewPill extends StatelessWidget {
  const _NewPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      // No vertical padding: labelSmall's own 16px line IS the pill, so it is
      // exactly as tall as the rating row it replaces — `ProviderCard` budgets
      // that row at 16 (`_textBlockHeight`), and a padded pill overflowed it.
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingS),
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        'Nouveau',
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

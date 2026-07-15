import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../models/review.dart';
import '../common/timed_cached_image.dart';

/// A single review, with a verified-booking badge, optional stylist
/// attribution, and optional before/after photos (tap to view full-screen).
class ReviewTile extends StatelessWidget {
  final Review review;

  /// « Signaler » (FR-REV-005, parity 2.14) — consumer surfaces pass this;
  /// null keeps the tile read-only (the pro « Avis » screen).
  final VoidCallback? onReport;

  const ReviewTile({super.key, required this.review, this.onReport});

  void _openPhoto(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(AppTheme.spacingM),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: TimedCachedImage(imageUrl: url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial =
        review.userName.isNotEmpty ? review.userName[0].toUpperCase() : '?';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.surfaceVariant,
          child: Text(
            initial,
            style: AppTextStyles.labelMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: AppTheme.spacingSM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      review.userName,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (review.verified) ...[
                    const SizedBox(width: AppTheme.spacingS),
                    const _VerifiedBadge(),
                  ],
                ],
              ),
              const SizedBox(height: AppTheme.spacingXS),
              Row(
                children: [
                  ...List.generate(
                    5,
                    (i) => Icon(
                      i < review.rating ? Icons.star : Icons.star_border,
                      size: AppTheme.iconXS,
                      color: AppColors.starRating,
                    ),
                  ),
                  if (review.artistName != null &&
                      review.artistName!.isNotEmpty) ...[
                    const SizedBox(width: AppTheme.spacingS),
                    Flexible(
                      child: Text(
                        'avec ${review.artistName}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppTheme.spacingXS),
              Text(
                Formatters.formatDateShort(review.createdAt),
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              if (review.text.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spacingXS),
                Text(
                  review.text,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (review.photoUrls.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spacingS),
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: review.photoUrls.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: AppTheme.spacingS),
                    itemBuilder: (context, index) {
                      final url = review.photoUrls[index];
                      return GestureDetector(
                        onTap: () => _openPhoto(context, url),
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusMedium),
                          child: TimedCachedImage(
                            imageUrl: url,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (onReport != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onReport,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Signaler',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingS, vertical: AppTheme.spacingXS),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified,
              size: AppTheme.iconXS, color: AppColors.success),
          const SizedBox(width: AppTheme.spacingXS),
          Text(
            'Réservation vérifiée',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.success),
          ),
        ],
      ),
    );
  }
}

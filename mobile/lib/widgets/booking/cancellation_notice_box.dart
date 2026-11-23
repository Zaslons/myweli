import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/cancellation_policy.dart';

/// The deposit sentence under « Annuler le rendez-vous ? », in its tone
/// (docs/design/consumer-app-truth.md §2.2): kept by the salon (error),
/// returned by the salon (success), or nothing decided yet (neutral).
class CancellationNoticeBox extends StatelessWidget {
  const CancellationNoticeBox({super.key, required this.notice});

  final CancellationNotice notice;

  @override
  Widget build(BuildContext context) {
    final accent = switch (notice.tone) {
      CancellationNoticeTone.kept => AppColors.error,
      CancellationNoticeTone.returned => AppColors.success,
      CancellationNoticeTone.neutral => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        // §13.1: `errorLight`/`successLight` are foregrounds (4.66:1 ON
        // white). Used as a fill they put `error` ink at 2.00:1 and
        // `success` ink at 1.85:1 — both illegible. A neutral tint carries
        // the ink (9.19:1 / 15.98:1) and the semantic hue moves to the
        // border, beside the glyph that already distinguishes it.
        color: AppColors.surfaceVariant,
        border: Border.all(
          color: notice.tone == CancellationNoticeTone.neutral
              ? AppColors.border
              : accent,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            notice.tone == CancellationNoticeTone.kept
                ? Icons.warning_amber_rounded
                : Icons.info_outline,
            size: AppTheme.iconS,
            color: accent,
          ),
          const SizedBox(width: AppTheme.spacingS),
          Expanded(
            child: Text(
              notice.text,
              style: AppTextStyles.bodySmall.copyWith(
                color: notice.tone == CancellationNoticeTone.kept
                    ? AppColors.error
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

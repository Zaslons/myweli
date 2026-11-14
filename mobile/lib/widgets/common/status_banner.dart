import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/text_styles.dart';

/// Where something stands, said above the screen it is about: a tinted box,
/// a glyph and a title in the state's colour, and its lines under the title
/// (SYSTEM.md §11 — the pattern « Vérification » drew for KYC, and
/// « Configuration » draws for MyWeli's validation of the salon, B0.18
/// salon-go-live-approval.md §6.2: « the KYC banner's pattern »). One
/// widget, so the two can never drift; moved out of pro_kyc_screen.dart
/// box for box (test/widget/pro_kyc_banner_parity_test.dart holds KYC to
/// what it drew before).
///
/// - **[color]** is a semantic token (`AppColors.warning`, `error`,
///   `success`, `textSecondary` for a neutral state): the glyph, the title
///   and the lines are drawn in it, on its 10% tint.
/// - **The glyph is not decoration** (§13.6): with the title it carries the
///   state in greyscale too. It is excluded from semantics, as an `Icon`
///   without a label is; a screen reader hears the title and the lines.
/// - **[lines]** each on their own line, in order — a refusal's sentence,
///   then the admin's note (a salon's typed text, never joined to the
///   sentence), then what to do next. Nothing is cut: no `maxLines`, a long
///   word wraps (§13.3).
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    this.lines = const [],
  });

  final Color color;
  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final lineStyle = AppTextStyles.bodySmall.copyWith(color: color);
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: AppTheme.iconM),
          const SizedBox(width: AppTheme.spacingSM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleSmall.copyWith(color: color),
                ),
                for (final line in lines) ...[
                  const SizedBox(height: AppTheme.spacingXS),
                  Text(line, style: lineStyle),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

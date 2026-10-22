import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/team_member.dart';

/// The role chip (module `access` §5.1): Propriétaire gold · Manager filled
/// black · Réception/Collaborateur outlined.
///
/// Gold is the Propriétaire's TINT and BORDER, never its text: `gold` at 11 px
/// on its own 12 % tint measured 2.79:1 on the background and 2.97:1 on a
/// card, under §13.1's 4.5:1 text floor. The label is ink, as on the web
/// (B7.1 — docs/design/pro-app-batch7.md §2.1, SYSTEM.md §21 row 28).
class TeamRoleChip extends StatelessWidget {
  const TeamRoleChip({super.key, required this.role});

  final TeamRole role;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, borderColor) = switch (role) {
      TeamRole.owner => (
        AppColors.gold.withValues(alpha: 0.12),
        AppColors.textPrimary,
        AppColors.gold.withValues(alpha: 0.5),
      ),
      TeamRole.manager => (
        AppColors.primary,
        AppColors.secondary,
        AppColors.primary,
      ),
      _ => (Colors.transparent, AppColors.textSecondary, AppColors.border),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingS,
        vertical: AppTheme.spacingXS,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        teamRoleLabel(role),
        style: AppTextStyles.labelSmall.copyWith(color: fg),
      ),
    );
  }
}

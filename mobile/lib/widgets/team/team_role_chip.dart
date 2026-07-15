import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/team_member.dart';

/// The role chip (module `access` §5.1): Propriétaire gold · Manager filled
/// black · Réception/Collaborateur outlined.
class TeamRoleChip extends StatelessWidget {
  const TeamRoleChip({super.key, required this.role});

  final TeamRole role;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, borderColor) = switch (role) {
      TeamRole.owner => (
          AppColors.gold.withValues(alpha: 0.12),
          AppColors.gold,
          AppColors.gold.withValues(alpha: 0.5),
        ),
      TeamRole.manager => (
          AppColors.primary,
          AppColors.secondary,
          AppColors.primary,
        ),
      _ => (
          Colors.transparent,
          AppColors.textSecondary,
          AppColors.border,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingS, vertical: AppTheme.spacingXS),
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

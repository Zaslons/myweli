import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

/// A pill showing the active commune (or "Toutes les communes" when none is
/// selected). Tapping it opens the commune picker. Used in the home header and
/// the provider list as the primary location lens.
class CommunePill extends StatelessWidget {
  final String? commune;
  final VoidCallback onTap;

  const CommunePill({
    super.key,
    required this.commune,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = commune ?? 'Toutes les communes';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingM,
          vertical: AppTheme.spacingS,
        ),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on,
                size: AppTheme.iconXS, color: AppColors.secondary),
            const SizedBox(width: AppTheme.spacingS),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacingXS),
            const Icon(
              Icons.keyboard_arrow_down,
              size: AppTheme.iconXS,
              color: AppColors.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

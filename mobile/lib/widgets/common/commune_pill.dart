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
    return ConstrainedBox(
      // §13.2 touch target ≥48 (minHeight, so it still grows with text scale).
      constraints: const BoxConstraints(minHeight: 48),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        // Center(widthFactor: 1) vertically centres the content in the ≥48 box
        // WITHOUT stretching to full width — a bare Container(alignment:) would
        // expand under the bounded width the home header hands it.
        child: Center(
          widthFactor: 1,
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
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

class AppSearchBar extends StatelessWidget {
  final VoidCallback onTap;

  const AppSearchBar({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // §13.3, twice over (A11 C5). `height: 48` was a fixed height around text
      // — the rule the document states in writing — with `bodyMedium` at 2×
      // measuring 40dp inside 46 of usable box: it survives 200% by 6dp and
      // clips above ≈2.3×. `minHeight` keeps §13.2's touch target and lets the
      // pill grow instead.
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(color: AppColors.borderStrong),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search,
              color: AppColors.textTertiary,
              size: AppTheme.iconM,
            ),
            const SizedBox(width: AppTheme.spacingSM),
            // The width twin, and the one place in this slice where an ellipsis
            // is the RIGHT answer rather than the false fix: this is placeholder
            // copy inside a fixed-shape pill, not a heading. Unflexed it wanted
            // 277dp at 2× and had 202, and ran off the side of the bar — the
            // third of the home screen's three overflows, in a widget no
            // register row had ever named.
            Expanded(
              child: Text(
                'Rechercher un salon…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';

/// A small monochrome segmented control (status filters / view switches) for the
/// admin console. Design: docs/design/admin-console-ui.md §2.
class AdminSegmentedControl extends StatelessWidget {
  const AdminSegmentedControl({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++) _seg(labels[i], i),
        ],
      ),
    );
  }

  Widget _seg(String label, int index) {
    final active = selected == index;
    return InkWell(
      onTap: () => onSelect(index),
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.secondary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: active ? Border.all(color: AppColors.border) : null,
        ),
        child: Text(
          label,
          style: (active ? AppTextStyles.titleSmall : AppTextStyles.bodyMedium)
              .copyWith(
            color: active ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

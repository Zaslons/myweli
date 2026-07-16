import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

class CategoryChips extends StatelessWidget {
  final String? selectedCategory;

  const CategoryChips({
    super.key,
    this.selectedCategory,
  });

  static const categories = [
    {'id': 'all', 'name': 'Tous', 'icon': Icons.all_inclusive},
    {'id': 'barber', 'name': 'Barbier', 'icon': Icons.content_cut},
    {'id': 'salon', 'name': 'Salon', 'icon': Icons.face},
    {'id': 'spa', 'name': 'Spa', 'icon': Icons.spa},
  ];

  @override
  Widget build(BuildContext context) {
    // A horizontal ListView demands a BOUNDED height, and that bound was the
    // constant 50 — so the chips clipped the moment the OS text scale grew
    // (§13.3, register row 15): the strip measured 50 at 1× and still 50 at 2×.
    // With only four categories there is nothing to virtualise, so a scroll view
    // over a Row lets the strip take its INTRINSIC height and grow with the text.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
      child: Row(
        children: [
          for (final category in categories) _chip(context, category),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, Map<String, Object> category) {
    final isSelected = selectedCategory == category['id'] ||
        (selectedCategory == null && category['id'] == 'all');

    return Padding(
      padding: const EdgeInsets.only(right: AppTheme.spacingS),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              category['icon'] as IconData,
              size: AppTheme.iconS,
              color: isSelected ? AppColors.secondary : AppColors.textPrimary,
            ),
            const SizedBox(width: AppTheme.spacingS),
            Text(category['name'] as String),
          ],
        ),
        selected: isSelected,
        onSelected: (selected) {
          if (category['id'] == 'all') {
            context.push('/providers');
          } else {
            context.push('/providers?category=${category['id']}');
          }
        },
        selectedColor: AppColors.primary,
        checkmarkColor: AppColors.secondary,
        labelStyle: AppTextStyles.bodyMedium.copyWith(
          color: isSelected ? AppColors.secondary : AppColors.textPrimary,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingM,
          vertical: AppTheme.spacingS,
        ),
      ),
    );
  }
}

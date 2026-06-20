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
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
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
                    size: 18,
                    color: isSelected
                        ? AppColors.secondary
                        : AppColors.textPrimary,
                  ),
                  const SizedBox(width: 6),
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
        },
      ),
    );
  }
}

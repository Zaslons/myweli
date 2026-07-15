import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/category_colors.dart';
import 'category_chips.dart';

class HighlightStories extends StatelessWidget {
  const HighlightStories({super.key});

  void _openCategory(BuildContext context, String id) {
    if (id == 'all') {
      context.push('/providers');
    } else {
      context.push('/providers?category=$id');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use the same source-of-truth as the chips, but render in a “stories” style.
    final items = CategoryChips.categories
        .where((c) => c['id'] != 'all')
        .cast<Map<String, Object>>()
        .toList();

    // Add a “Tous” story at the beginning.
    final all = CategoryChips.categories.firstWhere((c) => c['id'] == 'all');
    items.insert(0, all.cast<String, Object>());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
          child: Text(
            'Découvrir',
            style:
                AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: AppTheme.spacingS),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: AppTheme.spacingS),
            itemBuilder: (context, index) {
              final item = items[index];
              final id = item['id'] as String;
              final name = item['name'] as String;
              final icon = item['icon'] as IconData;
              final accent = categoryColor(id);

              return InkWell(
                onTap: () => _openCategory(context, id),
                borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                child: Container(
                  width: 88,
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppTheme.elevation1,
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(AppTheme.radiusXL),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                accent.withValues(alpha: 0.14),
                                AppColors.surface,
                              ],
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.secondary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: accent.withValues(alpha: 0.35)),
                              ),
                              child: Icon(icon, color: accent),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(AppTheme.spacingS),
                        child: Text(
                          name,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

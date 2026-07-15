import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../common/timed_cached_image.dart';

/// Bundled sample images used to simulate picking from the gallery without a
/// native picker dependency. The real picker (camera/gallery) slots in here
/// when the backend image pipeline lands.
const _sampleImages = [
  'asset:assets/images/providers/salon_excellence_photo.png',
  'asset:assets/images/providers/beaute_divine_photo.png',
  'asset:assets/images/providers/spa_relax_photo.png',
  'asset:assets/images/providers/barber_shop_pro_photo.png',
];

/// Shows a sheet of sample images; returns the chosen image source, or null.
Future<String?> showMockImagePicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.secondary,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXL)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Choisir une image', style: AppTextStyles.titleLarge),
          const SizedBox(height: AppTheme.spacingXS),
          Text(
            'Exemples (sélection simulée — l’appareil photo / la galerie '
            'arriveront avec le backend).',
            style:
                AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppTheme.spacingM),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: _sampleImages.map((url) {
              return GestureDetector(
                onTap: () => Navigator.pop(ctx, url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  child: TimedCachedImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ),
  );
}

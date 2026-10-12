import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/utils/category_colors.dart';

/// The glyph a salon's category wears on a map.
IconData salonCategoryIcon(String category) => switch (category) {
  'spa' => Icons.spa,
  'barber' => Icons.content_cut,
  'salon' => Icons.face_retouching_natural,
  _ => Icons.store_mall_directory,
};

/// A salon on a map — the « Carte » markers and the salon page's location
/// preview (docs/design/salon-location-map.md §2.1). The web's `SalonPin`
/// (`web/components/map/salon-pin.tsx`) draws the same thing.
///
/// A white disc, a 2dp ring and the icon in the category's colour
/// ([categoryColor], SYSTEM.md §3.6); a small heart badge when [isFavorite].
/// Sized by its parent — the `Marker`'s 48×48. Moved here unchanged from
/// `map_screen.dart`'s private `_SalonMarker`.
class SalonMapMarker extends StatelessWidget {
  final String category;
  final bool isFavorite;

  const SalonMapMarker({
    super.key,
    required this.category,
    this.isFavorite = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(category);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            boxShadow: AppTheme.elevation2,
          ),
          child: Center(
            child: Icon(
              salonCategoryIcon(category),
              color: color,
              size: AppTheme.iconS,
            ),
          ),
        ),
        if (isFavorite)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.favorite,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.favorite,
                size: AppTheme.iconXS,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

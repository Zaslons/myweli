import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// The canonical service-category → accent-color mapping (map markers + category
/// chips/stories). A bounded, deliberate exception to the monochrome identity —
/// use this single source everywhere a category is colored, never an inline hex.
/// Unknown categories fall back to [AppColors.primary]. Design:
/// docs/design/DESIGN-STANDARDS.md §7.
Color categoryColor(String category) => switch (category) {
      'spa' => AppColors.categorySpa,
      'barber' => AppColors.categoryBarber,
      'salon' => AppColors.categorySalon,
      _ => AppColors.primary,
    };

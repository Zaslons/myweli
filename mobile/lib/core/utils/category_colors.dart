import 'package:flutter/material.dart';

import '../constants/salon_categories.dart';
import '../theme/colors.dart';

/// The canonical service-category → accent-color mapping (map markers). A
/// bounded, deliberate exception to the monochrome identity — read from
/// [discoveryCategories], the one category list, and never inlined. Unknown
/// categories fall back to [AppColors.primary]. Design: SYSTEM.md §3.6.
Color categoryColor(String category) =>
    discoveryCategory(category)?.markerColor ?? AppColors.primary;

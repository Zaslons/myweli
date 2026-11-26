import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// One category a salon can choose, and every way the app shows it
/// (docs/design/consumer-search.md §2.4, decision 229).
///
/// **One list, so none can drift.** The Pro editor's list, the home's chips
/// and the map's marker table were three lists: the chips knew four
/// categories, the markers three, and a `nails` or `massage` salon could not
/// be reached by category anywhere in the app.
@immutable
class DiscoveryCategory {
  const DiscoveryCategory({
    required this.key,
    required this.label,
    required this.chipLabel,
    required this.chipIcon,
    required this.markerIcon,
    required this.markerColor,
  });

  /// The server's value (`GET /providers?category=`, the salon's own field).
  final String key;

  /// The long label: the salon page, the Pro editor, the admin console.
  final String label;

  /// The short label of a discovery chip — the website's (`web/lib/landing.ts`).
  final String chipLabel;

  /// The chip's glyph.
  final IconData chipIcon;

  /// The glyph a salon of this category wears on a map. Not the chip's: the
  /// map's drawing is shared with the website's `SalonPin`, which A4 does not
  /// change — `nails` and `massage` keep the generic shop and the brand ink,
  /// as before and as on the website.
  final IconData markerIcon;

  /// The map marker's accent (SYSTEM.md §3.6), read through `categoryColor`.
  final Color markerColor;
}

/// The listing categories a salon can choose (the canonical taxonomy —
/// mirrors the server's PATCH validation, pro-salon-lifecycle L1/L2), in the
/// order the chips show them, after « Tous ».
const discoveryCategories = [
  DiscoveryCategory(
    key: 'salon',
    label: 'Salon de coiffure',
    chipLabel: 'Coiffure',
    chipIcon: Icons.face,
    markerIcon: Icons.face_retouching_natural,
    markerColor: AppColors.categorySalon,
  ),
  DiscoveryCategory(
    key: 'barber',
    label: 'Barbier',
    chipLabel: 'Barbier',
    chipIcon: Icons.content_cut,
    markerIcon: Icons.content_cut,
    markerColor: AppColors.categoryBarber,
  ),
  DiscoveryCategory(
    key: 'nails',
    label: 'Onglerie',
    chipLabel: 'Onglerie',
    chipIcon: Icons.back_hand,
    markerIcon: kUnknownCategoryMarkerIcon,
    markerColor: AppColors.primary,
  ),
  DiscoveryCategory(
    key: 'spa',
    label: 'Spa',
    chipLabel: 'Spa',
    chipIcon: Icons.spa,
    markerIcon: Icons.spa,
    markerColor: AppColors.categorySpa,
  ),
  DiscoveryCategory(
    key: 'massage',
    label: 'Massage & bien-être',
    chipLabel: 'Massage',
    chipIcon: Icons.self_improvement,
    markerIcon: kUnknownCategoryMarkerIcon,
    markerColor: AppColors.primary,
  ),
];

/// The marker of a salon whose category is outside the taxonomy (a legacy
/// seed), and of the two the map's shared drawing has no glyph for.
const kUnknownCategoryMarkerIcon = Icons.store_mall_directory;

/// The category whose server value is [key]; null for anything else — a
/// legacy seed, or a stale `?category=` such as the website's old `nail`.
DiscoveryCategory? discoveryCategory(String? key) {
  for (final c in discoveryCategories) {
    if (c.key == key) return c;
  }
  return null;
}

/// `(key, long label)` of each category: the Pro editor's choices.
final List<(String, String)> salonCategories = [
  for (final c in discoveryCategories) (c.key, c.label),
];

/// The French label of a salon's [category] key — null for a key outside the
/// taxonomy (a legacy seed), which a caller hides rather than print a key.
String? salonCategoryLabel(String category) =>
    discoveryCategory(category)?.label;

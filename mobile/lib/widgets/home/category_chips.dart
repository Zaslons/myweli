import 'package:flutter/material.dart';

import '../../core/constants/salon_categories.dart';
import '../../core/theme/app_theme.dart';
import '../common/app_chip.dart';

/// « Tous » and the five categories of [discoveryCategories]
/// (docs/design/consumer-search.md §2.4, decision 229), on the home and on
/// the salon list.
///
/// [selected] is the lit category's key; null lights « Tous ».
/// [onSelected] gets the tapped chip's key — null for « Tous ». What a tap
/// does is the screen's: the home opens the list with that chip on, the list
/// narrows its search in place.
class CategoryChips extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelected;

  const CategoryChips({super.key, this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    // A horizontal ListView demands a BOUNDED height, and that bound was the
    // constant 50 — so the chips clipped the moment the OS text scale grew
    // (§13.3, register row 15): the strip measured 50 at 1× and still 50 at 2×.
    // Six chips are nothing to virtualise, so a scroll view over a Row lets
    // the strip take its INTRINSIC height and grow with the text.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
      child: Row(
        children: [
          _chip(
            label: 'Tous',
            icon: Icons.all_inclusive,
            isSelected: selected == null,
            key: null,
          ),
          for (final c in discoveryCategories)
            _chip(
              label: c.chipLabel,
              icon: c.chipIcon,
              isSelected: selected == c.key,
              key: c.key,
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required String? key,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: AppTheme.spacingS),
      child: AppChip.choice(
        label: label,
        icon: icon,
        selected: isSelected,
        onSelected: (_) => onSelected(key),
      ),
    );
  }
}

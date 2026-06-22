import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/booking_duration.dart';
import '../../core/utils/formatters.dart';

/// Hair-length chooser shown when a selected service prices/times by length.
/// Each chip shows the resulting total duration for that length.
class LengthVariantSelector extends StatelessWidget {
  final List<String> available;
  final String? selected;
  final int Function(String length) durationFor;
  final ValueChanged<String> onChanged;

  const LengthVariantSelector({
    super.key,
    required this.available,
    required this.selected,
    required this.durationFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Longueur des cheveux',
          style: AppTextStyles.labelMedium
              .copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppTheme.spacingS),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: available.map((length) {
            return ChoiceChip(
              label: Text(
                '${lengthVariantLabel(length)} · '
                '${Formatters.formatDuration(durationFor(length))}',
              ),
              selected: selected == length,
              onSelected: (_) => onChanged(length),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          'Les créneaux sont calculés selon cette durée. '
          'Le prix final est confirmé par le salon.',
          style:
              AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

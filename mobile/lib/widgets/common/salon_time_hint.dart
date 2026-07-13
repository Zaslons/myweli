import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/salon_time.dart';

/// « Heures affichées : heure du salon (Côte d'Ivoire) » — shown ONLY when
/// the device clock disagrees with the salon's (a traveler booking from
/// abroad); users in Côte d'Ivoire never see it. Consumer surfaces only.
/// Design: docs/design/timezone-salon-time.md §2.
class SalonTimeHint extends StatelessWidget {
  const SalonTimeHint({super.key, this.deviceOffsetOverride, this.padding});

  /// Test seam: inject the device offset instead of reading the real clock.
  final Duration? deviceOffsetOverride;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (!deviceOffsetDiffersFromSalon(deviceOffset: deviceOffsetOverride)) {
      return const SizedBox.shrink();
    }
    final text = Text(
      'Heures affichées : heure du salon (Côte d\'Ivoire)',
      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
    );
    if (padding == null) return text;
    return Padding(padding: padding!, child: text);
  }
}

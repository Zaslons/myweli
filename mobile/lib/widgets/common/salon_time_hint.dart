import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/salon_time.dart';

/// « Heures affichées : heure du salon (…) » — shown ONLY when the device
/// clock disagrees with the SALON's (a traveler booking from abroad); users
/// in the salon's own zone never see it. Consumer surfaces only.
/// Multi-pays MP2: takes the salon's IANA [tz] and its country's display
/// [countryLabel] (from the locality tree) — defaults keep the Wave-0 copy.
/// Design: docs/design/multi-pays-end-version.md §3.
class SalonTimeHint extends StatelessWidget {
  const SalonTimeHint({
    super.key,
    this.tz,
    this.countryLabel,
    this.deviceOffsetOverride,
    this.padding,
  });

  /// The salon's IANA timezone (null → Africa/Abidjan).
  final String? tz;

  /// The salon country's display name (null → Côte d'Ivoire).
  final String? countryLabel;

  /// Test seam: inject the device offset instead of reading the real clock.
  final Duration? deviceOffsetOverride;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (!deviceOffsetDiffersFromSalon(
      deviceOffset: deviceOffsetOverride,
      tz: tz,
    )) {
      return const SizedBox.shrink();
    }
    final text = Text(
      'Heures affichées : heure du salon (${countryLabel ?? 'Côte d\'Ivoire'})',
      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
    );
    if (padding == null) return text;
    return Padding(padding: padding!, child: text);
  }
}

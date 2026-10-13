import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/text_fit.dart';

/// The two figures at the top of « Mes rendez-vous → Historique »: how many
/// visits, and how much they cost.
class VisitSummary extends StatelessWidget {
  const VisitSummary({
    super.key,
    required this.visits,
    required this.spent,
    this.currency,
  });

  final int visits;
  final double spent;

  /// ISO-4217; null falls back in [Formatters.formatCurrency].
  final String? currency;

  static const TextStyle _valueStyle = AppTextStyles.titleLarge;
  static const TextStyle _labelStyle = AppTextStyles.bodySmall;

  @override
  Widget build(BuildContext context) {
    final metrics = <({String value, String label})>[
      (
        value: '$visits',
        // A13 — `== 1` printed « 0 visites »; French puts zero in the
        // singular. The number renders separately here, so this is the
        // noun-only helper.
        label: Formatters.plural(visits, 'visite', 'visites'),
      ),
      (
        value: Formatters.formatCurrency(spent, currency: currency),
        label: 'dépensés',
      ),
    ];

    // Two across, or one per row when the amount would not fit half the
    // width (docs/design/amounts-that-fit.md §2) — measured with the strings
    // and styles the tiles draw, never guessed from a text size. These were
    // two `Expanded`s in a plain `Row`: a long total broke inside its number,
    // and the tile whose unit wrapped stood taller than its neighbour.
    return LayoutBuilder(
      builder: (context, box) {
        final columns = TextFit.of(context).columns(
          candidates: const [2, 1],
          cellWidth: (n) =>
              (box.maxWidth - (n - 1) * AppTheme.spacingM) / n -
              2 * AppTheme.spacingM,
          texts: [
            for (final m in metrics) ...[
              (text: m.value, style: _valueStyle),
              (text: m.label, style: _labelStyle),
            ],
          ],
        );
        return Column(
          children: [
            for (var i = 0; i < metrics.length; i += columns) ...[
              if (i > 0) const SizedBox(height: AppTheme.spacingM),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (k, m)
                        in metrics.skip(i).take(columns).indexed) ...[
                      if (k > 0) const SizedBox(width: AppTheme.spacingM),
                      Expanded(child: _metric(m.value, m.label)),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _metric(String value, String label) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: _valueStyle),
          const SizedBox(height: AppTheme.spacingXS),
          Text(
            label,
            style: _labelStyle.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

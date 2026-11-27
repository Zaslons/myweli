import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/revenue_wording.dart';

/// A change against the comparison (docs/design/pro-revenue-analytics.md
/// §3.6, §12.1; SYSTEM.md §11.3): an arrow glyph and the signed figure —
/// « ▲ +12 % », « ▼ −1,2 pt », « stable », « nouveau ».
///
/// **Never the colour alone** (§13): the glyph and the sign carry the
/// direction in greyscale, and a screen reader hears the sentence
/// (« en hausse de 12 % par rapport à octobre 2026 »). The colour follows
/// the figure's good direction — `success` / `error` — and « stable » is
/// `textSecondary`.
///
/// One `Text.rich`, the glyph a `WidgetSpan`: in a narrow tile at 200 % it
/// wraps as text does, and never overflows a row.
class DeltaBadge extends StatelessWidget {
  const DeltaBadge(this.delta, {super.key});

  final RevenueDelta delta;

  static const TextStyle textStyle = AppTextStyles.labelMedium;

  static Color colorOf(RevenueDeltaTone tone) => switch (tone) {
    RevenueDeltaTone.good => AppColors.success,
    RevenueDeltaTone.bad => AppColors.error,
    RevenueDeltaTone.neutral => AppColors.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final color = colorOf(delta.tone);
    final up = delta.up;
    return Semantics(
      label: delta.spoken,
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            children: [
              if (up != null) ...[
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(
                    up ? Icons.arrow_upward : Icons.arrow_downward,
                    size: AppTheme.iconS,
                    color: color,
                  ),
                ),
                // A no-break space: the glyph stays with its figure.
                const TextSpan(text: ' '),
              ],
              TextSpan(text: delta.text),
            ],
          ),
          style: textStyle.copyWith(color: color),
        ),
      ),
    );
  }
}

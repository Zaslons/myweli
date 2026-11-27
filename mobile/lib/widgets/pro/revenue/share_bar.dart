import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';

/// A row's share of the period's « Réalisé » (pro-revenue-analytics.md §4.7,
/// §12.1; SYSTEM.md §11.3): a track the row's width, `surfaceVariant`, filled
/// in `primary` to [share], `radiusPill`.
///
/// **Excluded from semantics** — its row says the share in words (« 34 % du
/// réalisé »); a bar read as « image » would say nothing more.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.share});

  /// 0–1, the server's (its shares of one axis add up to 1).
  final double share;

  /// 4dp: a line under the row, not a control (§5 « What §5 does not
  /// govern » — a drawing's own dimension, named once here).
  static const double height = AppTheme.spacingXS;

  @override
  Widget build(BuildContext context) {
    final fill = share.clamp(0.0, 1.0);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AppColors.surfaceVariant),
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: fill,
                child: const ColoredBox(color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

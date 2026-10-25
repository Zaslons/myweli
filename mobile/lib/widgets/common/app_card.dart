import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';

/// The card (SYSTEM.md §11.3, §3.1): `secondary` on the page's `background`,
/// `radiusXL`, elevation 0, `spacingM` inside — the low-contrast lift that
/// carries the layout without borders or shadows. Built in B9.8
/// (docs/design/hygiene-batch9.md §2.7.2); every card on a screen is one.
///
/// [onTap] makes the whole card the target, its ripple clipped to the corner,
/// announced as a button. [outlined] adds the `borderStrong` hairline for a
/// card that is a control (a choice, a selection) — not "to make it pop"
/// (§3.1).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.spacingM),
    this.onTap,
    this.outlined = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    final tap = onTap;
    final card = Material(
      color: AppColors.secondary,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        side: outlined
            ? const BorderSide(color: AppColors.borderStrong)
            : BorderSide.none,
      ),
      child: tap == null ? content : InkWell(onTap: tap, child: content),
    );
    if (tap == null) return card;
    // One node for the whole card: its text is the button's label.
    return MergeSemantics(
      child: Semantics(button: true, enabled: true, child: card),
    );
  }
}

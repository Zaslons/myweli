import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';

/// The card (SYSTEM.md §11.3, §3.1, §8): `secondary` on the page's
/// `background`, `radiusXL`, **elevation 0**, `spacingM` inside — the
/// low-contrast lift that carries the layout without borders or shadows.
/// Built in B9.8 (docs/design/hygiene-batch9.md §2.7.2, §2.7.3); every card
/// on a screen is one, and `async_states_pin_test.dart`'s card pin holds it.
///
/// [padding] other than `spacingM` needs a reason the call site writes down:
/// zero around a list of rows or a photo edge to edge, an arithmetic one.
///
/// The card is one **container** node for a screen reader, as Material's
/// `Card` is (`semanticContainer`): what it says is read together, and a
/// control inside it — the heart of a salon card, a row's switch — stays a
/// node of its own a screen reader can reach. Not a merge, which would
/// swallow them.
///
/// [onTap] makes the whole card the target, its ripple clipped to the corner,
/// announced as a button whose label is the card's text.
///
/// [outlined] adds the `borderStrong` hairline for a card that is a control
/// (a choice, a step that opens), never "to make it pop" (§3.1); [selected]
/// is the chosen one: a 2px `primary` line on the same white card (Q13).
/// When the card is the target ([onTap]) it is said to a screen reader, not
/// only drawn; when its control is inside it — a step that opens by its
/// header — that control says it (« développé »).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.spacingM),
    this.onTap,
    this.outlined = false,
    this.selected = false,
  }) : assert(!selected || outlined, 'a chosen card is a control card');

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool outlined;
  final bool selected;

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
        side: !outlined
            ? BorderSide.none
            : selected
            ? const BorderSide(color: AppColors.primary, width: 2)
            : const BorderSide(color: AppColors.borderStrong),
      ),
      child: tap == null ? content : InkWell(onTap: tap, child: content),
    );
    return Semantics(
      container: true,
      button: tap != null ? true : null,
      enabled: tap != null ? true : null,
      selected: outlined && tap != null ? selected : null,
      child: card,
    );
  }
}

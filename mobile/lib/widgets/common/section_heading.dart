import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

/// A section title, with an optional action beside it (A11 C5).
///
/// ## Why this is shared
///
/// The pattern existed **three** times and the three had already drifted apart:
/// two inline `Row(spaceBetween)`s in `home_screen` at `titleLarge`, and a
/// private `_SectionCard` in `provider_detail_screen` using `Spacer` instead,
/// at `titleMedium`, with seven call sites. Only the private one carried §13.2's
/// `minHeight: 48` on a tappable header; only the public ones were inside a
/// gate. All three shared the actual bug — an unflexed `Text` beside an
/// unflexed action — and it went unnoticed on the salon page for exactly as long
/// as that screen stayed out of the width gate.
///
/// §11's rule is that a pattern appearing twice becomes a shared widget and a
/// third inline copy is a review failure. This was the third.
///
/// ## Why a `Wrap` and not a `Row`
///
/// At 200% text « Derniers rendez-vous » + « Voir tout » wants **564dp** and a
/// 360dp phone gives it **328**. Three ways out, and two of them are worse than
/// the bug:
///
/// * **`maxLines: 1, overflow: ellipsis`** — turns every gate in the repo green
///   and ships « Derniers rendez… ». `expectNoUndeclaredTruncation` skips a
///   declared ellipsis by design, so nothing would have caught it;
///   `_expectHeadingIsWhole` now exists specifically to forbid it.
/// * **`Expanded` on the title** — honest, but at 360×2× it leaves the heading
///   ~171dp and « Derniers rendez-vous » becomes three narrow lines beside a
///   button.
/// * **`Wrap`** — at 1× `spaceBetween` puts the title left and the action right,
///   pixel-identical to the `Row` it replaces. When they stop fitting, the title
///   takes the **full width** and the action moves to its own line beneath it.
///   Two lines instead of three, a full-size tap target, and no arithmetic
///   anywhere.
///
/// `Wrap` is 19-times established here, and this gate has already proved it
/// scale-safe: `LegalConsentText` is a `Wrap` and is green at all six
/// width×scale configurations (§21 row 49).
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.style,
    this.action,
    this.onTap,
  });

  final String title;

  /// Defaults to `titleLarge`. The salon page's cards pass `titleMedium`,
  /// because there the heading sits inside a card rather than over a section of
  /// the page — a real difference, and the only one worth a parameter.
  final TextStyle? style;

  /// « Voir tout », an accordion chevron, or nothing.
  final Widget? action;

  /// Makes the whole heading tappable — the salon page's Services accordion.
  /// Brings §13.2's floor with it: a 48dp minimum only when there is something
  /// to hit, because an untappable heading is not a touch target.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // **`double.infinity` is load-bearing, and the golden is what found it.**
    // A `Wrap` shrink-wraps under loose constraints, and both call sites put it
    // in a `Column(crossAxisAlignment: start)` — so `spaceBetween` had no free
    // space to distribute and « Voir tout » rendered snug against the title
    // instead of at the right edge. The `Row` it replaced defaulted to
    // `mainAxisSize: max` and never had the problem. Nothing in the width gate
    // could see it: the layout was correct, only the alignment was not.
    final heading = SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        // Only visible once the action wraps to its own line, which is the whole
        // point of the shape.
        runSpacing: AppTheme.spacingS,
        children: [
          Text(
            title,
            style: (style ?? AppTextStyles.titleLarge).copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );

    // **The padding belongs to the HEADING, not to the tap target** (A11 C8).
    //
    // It was inside the `onTap != null` branch, and that was an extraction bug:
    // the `_SectionCard` this replaced applied
    // `Container(padding: symmetric(vertical: spacingXS))` **unconditionally**,
    // outside its `InkWell`. Only 1 of the 7 salon-detail sections passes a tap
    // handler, so the other six — Vos rendez-vous ici, Contact, Photos,
    // Avant/Après, Avis, À propos — silently lost 8dp and sat tighter against
    // their content.
    //
    // Worse, C5 regenerated `consumer_provider_detail.png` in the same commit,
    // so the loss was written into the baseline as truth. That is §20.1's named
    // failure mode — a golden cannot tell you it photographed a regression —
    // and it is why the review that found this was worth running after green.
    final padded = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXS),
      child: heading,
    );

    if (onTap == null) return padded;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48), // §13.2 touch target
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXS),
          child: heading,
        ),
      ),
    );
  }
}

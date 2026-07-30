import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/text_styles.dart';

/// A label on the left and its value on the right — « Total » · « 25 000 FCFA »
/// (A12).
///
/// ## Why this is a widget and not eleven `Row`s
///
/// It was eleven `Row`s — nine found by the census, one more when the widget
/// landed, and an eleventh the adversarial review found on the booking
/// confirmation screen — every one of them
/// `Row(mainAxisAlignment: spaceBetween, children: [Text(label), Text(value)])`
/// with **neither child flexed**, so a `RenderFlex` hands each its full
/// intrinsic width and the row overflows rather than either side giving way.
/// Measured at 360dp × 200%:
///
/// | | over by |
/// |---|---|
/// | deposit settings, « Acompte payé en ligne » | ~150dp |
/// | booking confirmation, « Acompte (30%) » | ~123dp |
/// | booking confirmation, « Solde à régler au salon » | ~117dp |
/// | booking hub, the pinned « Total » bar | ~36dp |
///
/// The first three are on the **deposit** screens and the fourth is on the bar
/// that is always visible while a booking is being built — i.e. the money a
/// user is about to be asked for, on the screen where they are asked for it.
///
/// The census that found them is §21 row 68's, and it named three; a sweep for
/// the shape found **twenty**. The count is why this is a component: the same
/// two-line fix applied nine times is the eighth copy §11 calls a review
/// failure, and it leaves the tenth site to be written wrong. Two more have
/// arrived since, which is the argument rather than an exception to it.
///
/// ## The shape
///
/// A [Wrap], the answer §13.3 already takes for a title and its action
/// (`SectionHeading`) and for a name and its badge (`ReviewTile`): while both
/// fit they sit at opposite ends exactly as the `Row` put them, and when they
/// stop fitting the **value drops to its own line** instead of pushing the
/// label off the screen.
///
/// The [SizedBox] is load-bearing, as it is at both precedents: a `Wrap`
/// shrink-wraps, so `WrapAlignment.spaceBetween` inside one has no free space
/// to distribute and the value would sit against the label.
class LabelValueRow extends StatelessWidget {
  const LabelValueRow({
    super.key,
    required this.label,
    required this.value,
    this.labelStyle,
    this.valueStyle,
  });

  final String label;
  final String value;

  /// Defaults to `bodyMedium` — the workhorse (§4), and what six of the nine
  /// call sites already passed.
  final TextStyle? labelStyle;

  /// Defaults to [labelStyle], so a row with one style names it once.
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final label0 = labelStyle ?? AppTextStyles.bodyMedium;
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        // Only visible while both are on one line; `runSpacing` is what
        // separates them once the value wraps.
        spacing: AppTheme.spacingS,
        runSpacing: AppTheme.spacingXS,
        children: [
          Text(label, style: label0),
          Text(value, style: valueStyle ?? label0),
        ],
      ),
    );
  }
}

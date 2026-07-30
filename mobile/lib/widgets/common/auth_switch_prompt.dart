import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

/// « Pas encore de compte ? **S'inscrire** » — the line that sends someone to
/// the other auth screen (A11 C8).
///
/// ## Why it is a widget and not two `Row`s
///
/// It was two `Row`s, and both overflowed. `pro_login_screen.dart` ran **149px**
/// past a 360dp screen at 200% text, `pro_register_screen.dart` the same: a
/// centred `Row` with a `Text` and a `TextButton`, neither able to give way, so
/// the sentence and its link simply ran off the edge. The overflow was constant
/// across the width range — 149px at 360, 134 at 375, 119 at 390 — which is the
/// signature of content with a fixed intrinsic width rather than a layout that
/// adapts badly.
///
/// The prompt sits at the bottom of the **first screen a pro ever sees**, and it
/// is the only route to registration on it.
///
/// A [Wrap] is the same fix §13.3 already takes for headings (`SectionHeading`,
/// C5): when the two parts no longer fit on one line, the link drops to its own
/// line instead of being pushed out of the window. Below that width nothing
/// moves — a Wrap with room lays out exactly like the Row it replaces.
///
/// The [SizedBox] is load-bearing for the same reason it is in `SectionHeading`:
/// **a Wrap shrink-wraps**, so `WrapAlignment.center` inside a shrink-wrapped
/// box centres nothing. Given the full width, it centres each run.
class AuthSwitchPrompt extends StatelessWidget {
  const AuthSwitchPrompt({
    super.key,
    required this.question,
    required this.actionLabel,
    required this.onPressed,
  });

  /// « Pas encore de compte ? » — note the trailing space is NOT needed here;
  /// the Wrap's spacing provides the gap, and a trailing space inside a wrapped
  /// run is invisible at the end of a line and wrong in the middle of one.
  final String question;

  /// « S'inscrire ».
  final String actionLabel;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            question,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          // No SizedBox gap: the TextButton brings its own horizontal padding,
          // and a fixed gap would sit at the end of the first line when the
          // button wraps.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXS),
            child: TextButton(onPressed: onPressed, child: Text(actionLabel)),
          ),
        ],
      ),
    );
  }
}

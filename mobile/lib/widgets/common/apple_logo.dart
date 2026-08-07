import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show AppleLogoPainter;

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';

/// The official Apple mark for « Continuer avec Apple », mirroring
/// `GoogleGLogo` on the other button.
///
/// **The vector is Apple's own**, not one we drew: `AppleLogoPainter` is
/// exported by the `sign_in_with_apple` plugin (`sign_in_with_apple.dart:20`),
/// so we get the mark Apple ships without bundling a new asset or reproducing a
/// trademark by hand.
class AppleLogo extends StatelessWidget {
  const AppleLogo({super.key, this.size = AppTheme.iconS, this.color});

  /// The mark's HEIGHT. Its width is derived — see [build].
  final double size;

  /// Defaults to the button's resolved foreground, which is what keeps it
  /// legible when the button is disabled. See [build].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // `AppleLogoPainter` scales its path by the Size it is handed, so a SQUARE
    // box STRETCHES the mark. The plugin's own button draws it at 25:31
    // (`sign_in_with_apple_button.dart:120-121`); match that or the apple is
    // visibly fat next to Google's pixel-perfect « G ».
    final width = size * 25 / 31;

    // Resolved from the button rather than hardcoded white. `AppButton`'s
    // primary variant fills with `surfaceVariant` (light grey) when disabled —
    // and a `leading:` widget, unlike an `Icon`, is NOT tinted by
    // `foregroundColor`. A hardcoded white mark would simply vanish while
    // `auth.isLoading`. `ButtonStyleButton` wraps its child in an
    // `IconTheme.merge` carrying the state-aware foreground, so reading it here
    // gives white when enabled and `textDisabled` when not, with no logic at
    // any call site.
    final resolved =
        color ?? IconTheme.of(context).color ?? AppColors.secondary;

    return ExcludeSemantics(
      // Decorative (SYSTEM.md §13.4): the button's label already says
      // « Apple », so labelling the mark would have a screen reader announce
      // the provider twice.
      child: CustomPaint(
        size: Size(width, size),
        painter: AppleLogoPainter(color: resolved),
      ),
    );
  }
}

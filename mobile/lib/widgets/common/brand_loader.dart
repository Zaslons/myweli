import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../core/a11y/reduce_motion.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

/// The MyWeli in-app loading animation (the `mark_loader`) — used for every
/// loading / refresh state. `standard` cut for full-screen / page loads, `fast`
/// for inline / button / list spinners. Monochrome: the black cut on light
/// surfaces, the white cut on dark (dark mode / dark backgrounds).
///
/// The app-open animation is the separate `loader_v2` set (wired at the splash
/// in P4). Design: docs/design/branding-integration.md.
///
/// **Reduced motion (§9, A8).** This is an infinitely repeating Lottie, and
/// `repeat()` is precisely what the framework's 5 % scale does not reach — so
/// the widget reads the flag itself. Under it the mark holds a still frame and
/// the standard cut grows a « Chargement… » caption, because a frozen logo and
/// a broken screen look identical.
///
/// The [semanticsLabel] is **not** conditional on the flag: before A8 this
/// widget had no `Semantics` at all, so at 68 call sites a screen reader
/// reached the app's most common transient state and said nothing.
class BrandLoader extends StatelessWidget {
  const BrandLoader({
    super.key,
    this.size = 48,
    this.fast = false,
    this.onDark = false,
  });

  /// Rendered width/height (square).
  final double size;

  /// The fast (~1.2 s) cut for inline / small spinners; else the standard (~2.7 s).
  ///
  /// It also decides whether the reduced-motion caption is drawn: `fast` marks
  /// the inline case — inside a button, a list footer, a thumbnail — where there
  /// is no room for a line of text and the surrounding UI already says what is
  /// happening. The label below is spoken either way.
  final bool fast;

  /// Use the white cut (for dark backgrounds / dark mode).
  final bool onDark;

  /// The one string this widget says and shows. §16's sentence-case rule; the
  /// ellipsis is the character, not three dots.
  static const semanticsLabel = 'Chargement…';

  String get _asset {
    final base = fast ? 'myweli_mark_loader_fast' : 'myweli_mark_loader';
    return 'assets/lottie/loader/$base${onDark ? '_white' : ''}.json';
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = reduceMotionOf(context);

    final mark = SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        _asset,
        fit: BoxFit.contain,
        // A still frame, not an invisible one that keeps ticking: with
        // `animate: false` the package never starts a controller at all
        // (`lottie.dart:415`), so the widget stops scheduling frames.
        animate: !reduceMotion,
        repeat: !reduceMotion,
      ),
    );

    return Semantics(
      container: true,
      label: semanticsLabel,
      // Otherwise the caption below announces a second time — one state, two
      // voices. `motion_test.dart` asserts the node COUNT for this reason.
      excludeSemantics: true,
      child: Center(
        child: reduceMotion && !fast
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  mark,
                  const SizedBox(height: AppTheme.spacingS),
                  Text(
                    semanticsLabel,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                      color:
                          onDark ? AppColors.surface : AppColors.textSecondary,
                    ),
                  ),
                ],
              )
            : mark,
      ),
    );
  }
}

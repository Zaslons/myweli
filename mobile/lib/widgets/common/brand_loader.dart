import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

    // **Not a frozen Lottie — the static brand mark.** `animate: false` does
    // stop the ticker (`lottie.dart:415` never starts a controller), and A8's
    // first attempt shipped exactly that. The golden showed what it actually
    // renders: **nothing**. Frame 0 of a draw-on loader is an empty canvas, so
    // "freeze the mark" froze a blank box with a caption under it. The brand
    // already has the still asset the animation draws towards; use it.
    final mark = SizedBox(
      width: size,
      height: size,
      child: reduceMotion
          ? SvgPicture.asset(
              'assets/brand/myweli_mark_${onDark ? 'white' : 'black'}.svg',
              width: size,
              height: size,
              fit: BoxFit.contain,
            )
          : Lottie.asset(_asset, fit: BoxFit.contain, repeat: true),
    );

    return Semantics(
      container: true,
      label: semanticsLabel,
      // Otherwise the caption below announces a second time — one state, two
      // voices. `motion_test.dart` asserts the node COUNT for this reason.
      excludeSemantics: true,
      child: Center(
        child: reduceMotion && !fast
            ? LayoutBuilder(
                builder: (context, constraints) =>
                    _captionFitsIn(context, constraints)
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          mark,
                          const SizedBox(height: AppTheme.spacingS),
                          Text(
                            semanticsLabel,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: onDark
                                  ? AppColors.surface
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      )
                    : mark,
              )
            : mark,
      ),
    );
  }

  /// Is there room for the caption? **Measured against the incoming
  /// constraints, not guessed from [size].**
  ///
  /// `LoadingIndicator` never passes `fast`, so ~50 sites take the caption
  /// branch — including a **60×60 avatar placeholder**, where 40 mark + 8 gap +
  /// a wrapped two-line caption overflowed by **44px**. Fixing that one call
  /// site would have left the next 60px box to re-create it.
  ///
  /// The arithmetic is the whole risk (register row 15: a computed bound that
  /// under-provisions clips silently, and one that over-provisions is just as
  /// wrong), so it uses the real line height at the real text scale rather than
  /// a magic threshold — and `motion_test.dart` checks BOTH directions,
  /// including 2×.
  bool _captionFitsIn(BuildContext context, BoxConstraints constraints) {
    if (!constraints.hasBoundedHeight) return true;
    final line =
        MediaQuery.textScalerOf(
          context,
        ).scale(AppTextStyles.bodySmall.fontSize!) *
        AppTextStyles.bodySmall.height!;
    return constraints.maxHeight >= size + AppTheme.spacingS + line;
  }
}

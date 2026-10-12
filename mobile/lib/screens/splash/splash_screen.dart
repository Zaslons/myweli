import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import '../../core/a11y/reduce_motion.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import 'open_animation_player.dart';

/// App-open screen: the MyWeli open animation (`loader_v2`, the *mixed* cut)
/// over the light `#FAFAFA` the native splash ends on, then `/home`.
/// Design: docs/design/pro-open-animation.md §2.8 (branding-integration.md P4).
///
/// **The whole file, once, then a rest on the finished mark** — « MyWeli »
/// draws, holds, morphs into the mark, the mark spins (erases, redraws), and
/// the screen leaves [OpenAnimationPlayer.rest] after the end frame is drawn,
/// stopped on it. The clock is the animation's controller: no wall-clock
/// hold (the old 3800 ms left at frame ≤ 95, on a mostly erased mark).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// The consumer open animation.
  static const asset = 'assets/lottie/open/myweli_loader_mixed.json';

  /// What a screen reader announces — the wordmark the animation draws.
  static const semanticsLabel = 'MyWeli';

  /// The open animation's on-screen width — shared with the Pro splash
  /// (`ProSplashScreen`), so both apps draw the mark at the same scale.
  static const double animationWidth = 220;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final OpenAnimationPlayer _player = OpenAnimationPlayer(vsync: this);

  /// The first pass (or the broken-asset hold) has begun — it runs once.
  bool _started = false;
  Timer? _fallbackTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion holds the wordmark, then the finished mark, for the same
    // length (§2.4, §2.8): the user asked the OS to stop movement, not to be
    // shown a shorter or a different app. Applied mid-pass too.
    _player.reduceMotion = reduceMotionOf(context);
  }

  void _onLoaded(LottieComposition composition) {
    // Once: a second first pass would silently lengthen the boot.
    if (_started) return;
    _started = true;
    _player.play(composition).then((_) => _leave());
  }

  void _onAssetFailed() {
    if (_started) return;
    _started = true;
    // A broken build, never a stranded user: the still mark stands for one
    // rest — bounded, and long enough not to flash — then the app.
    _fallbackTimer = Timer(OpenAnimationPlayer.rest, _leave);
  }

  void _leave() {
    if (!mounted) return;
    // Always go to home — users can browse without signing in.
    context.go('/home');
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Light — matches the native splash (#FAFAFA) and flows into the app.
      backgroundColor: AppColors.surface,
      body: Center(
        child: Semantics(
          label: SplashScreen.semanticsLabel,
          image: true,
          child: ExcludeSemantics(
            // The player drives the progress in both modes. Under reduced
            // motion it pins a still that HAS ink — frame 0 of this
            // composition is an empty canvas (every glyph opens at opacity 0),
            // which is why `animate: false` once rendered a blank splash
            // (SYSTEM.md §9.1.1).
            child: Lottie.asset(
              SplashScreen.asset,
              controller: _player.controller,
              onLoaded: _onLoaded,
              width: SplashScreen.animationWidth,
              errorBuilder: (context, error, stackTrace) {
                // It had none: a failed decode rendered nothing for the whole
                // hold. Now the still brand mark, as the Pro splash and
                // `BrandLoader` hold it — never typed text
                // (branding-integration.md §2).
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _onAssetFailed(),
                );
                return SvgPicture.asset(
                  'assets/brand/myweli_mark_black.svg',
                  height: AppTheme.iconXL,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

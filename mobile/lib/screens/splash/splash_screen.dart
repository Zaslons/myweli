import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import '../../core/a11y/reduce_motion.dart';
import '../../core/theme/colors.dart';

/// App-open screen: the MyWeli open animation (`loader_v2`) over the brand-black
/// background, continuing the native splash while the app initialises, then
/// routing on. Design: docs/design/branding-integration.md.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // Hold the splash long enough to show the open animation (the `loader_v2`
  // intro + redraw cycle runs ~5 s). Tune here.
  // A content timer, not motion: how long the open animation is given to
  // play, the same category as the story reel's 6 s reading time. §9's ladder
  // tops out at 400 ms and could not name it.
  static const _minSplashDuration = Duration(milliseconds: 3800); // ds-ignore

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(_minSplashDuration);
    if (!mounted) return;
    // Always go to home — users can browse without signing in.
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = reduceMotionOf(context);
    return Scaffold(
      // Light — matches the native splash (#FAFAFA) and flows into the app.
      backgroundColor: AppColors.surface,
      body: Center(
        // Reduced motion holds the animation's END frame and changes NOTHING
        // else (§9, A8). The brand, the colours, the 220px and the 3800 ms
        // hold all stay: the user asked the OS to stop movement, not to be
        // shown a different app.
        //
        // **`AlwaysStoppedAnimation`, not `animate: false`.** Supplying a
        // controller is what stops the ticker (`lottie.dart:415` starts
        // nothing when one is given) — and `animate: false` alone leaves the
        // progress at 0, which in this composition is an EMPTY CANVAS: all six
        // glyph layers open at opacity 0 and `redraw` is not in-point until
        // frame 54. The first version of this rendered a blank #FAFAFA screen
        // for the full hold. A constant animation needs no vsync and no
        // disposal, so there is no controller to leak.
        child: Lottie.asset(
          'assets/lottie/open/myweli_loader_mixed.json',
          width: 220,
          controller: reduceMotion ? const AlwaysStoppedAnimation(1) : null,
          repeat: !reduceMotion,
        ),
      ),
    );
  }
}

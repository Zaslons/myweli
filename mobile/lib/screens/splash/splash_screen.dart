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
        // Reduced motion freezes the mark and changes NOTHING else (§9, A8).
        // The brand, the colours, the 220px and the 3800 ms hold above all
        // stay: the user asked the OS to stop movement, not to be shown a
        // different app, and cutting the hold would give them a different boot
        // sequence from everyone else. A native splash is a still image too.
        child: Lottie.asset(
          'assets/lottie/open/myweli_loader_mixed.json',
          width: 220,
          animate: !reduceMotion,
          repeat: !reduceMotion,
        ),
      ),
    );
  }
}

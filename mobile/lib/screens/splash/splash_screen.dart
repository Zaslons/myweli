import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

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
  static const _minSplashDuration = Duration(milliseconds: 3800);

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
    return Scaffold(
      // Light — matches the native splash (#FAFAFA) and flows into the app.
      backgroundColor: AppColors.surface,
      body: Center(
        child: Lottie.asset(
          'assets/lottie/open/myweli_loader_mixed.json',
          width: 220,
          repeat: true,
        ),
      ),
    );
  }
}

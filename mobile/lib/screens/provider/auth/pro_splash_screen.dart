import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/motion.dart';
import '../../../core/theme/text_styles.dart';
import '../../../providers/pro_auth_provider.dart';

class ProSplashScreen extends StatefulWidget {
  const ProSplashScreen({super.key});

  @override
  State<ProSplashScreen> createState() => _ProSplashScreenState();
}

class _ProSplashScreenState extends State<ProSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // §9 by its USE column, not by nearest number. A logo fading in is an
    // *entering surface* → `motionEmphasis`, whose curve decelerates. The
    // first pass took `motionSlow` because 1500 is numerically nearest to 400
    // — and `easeInOutCubic` still eases IN, so it swapped one violation of
    // "entering decelerates" for a quieter one. Proximity only breaks ties
    // WITHIN a use.
    _controller = AnimationController(
      duration: AppMotion.emphasis,
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: AppMotion.emphasisCurve),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: AppMotion.emphasisCurve),
      ),
    );

    _controller.forward();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    await authProvider.loadCurrentProvider();

    if (!mounted) return;

    if (authProvider.isAuthenticated) {
      context.go(authProvider.isStaff ? '/pro/staff' : '/pro/dashboard');
    } else {
      context.go('/pro/login');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo placeholder - replace with actual logo
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppTheme.radiusXXL),
                  ),
                  child: const Icon(
                    Icons.business,
                    size: AppTheme.iconXL,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingL),
                Text(
                  'MyWeli Pro',
                  style: AppTextStyles.displaySmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingS),
                Text(
                  'Pour les professionnels',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingXL),
                const LoadingIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

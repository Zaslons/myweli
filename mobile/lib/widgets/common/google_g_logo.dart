import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The official multicolor Google « G » — Google's sign-in branding
/// guidelines expect it on every « Continuer avec Google » button.
class GoogleGLogo extends StatelessWidget {
  const GoogleGLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/brand/google_g_logo.svg',
        width: size,
        height: size,
      );
}

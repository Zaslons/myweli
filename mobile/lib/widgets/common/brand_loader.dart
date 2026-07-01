import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// The MyWeli in-app loading animation (the `mark_loader`) — used for every
/// loading / refresh state. `standard` cut for full-screen / page loads, `fast`
/// for inline / button / list spinners. Monochrome: the black cut on light
/// surfaces, the white cut on dark (dark mode / dark backgrounds).
///
/// The app-open animation is the separate `loader_v2` set (wired at the splash
/// in P4). Design: docs/design/branding-integration.md.
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
  final bool fast;

  /// Use the white cut (for dark backgrounds / dark mode).
  final bool onDark;

  String get _asset {
    final base = fast ? 'myweli_mark_loader_fast' : 'myweli_mark_loader';
    return 'assets/lottie/loader/$base${onDark ? '_white' : ''}.json';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Lottie.asset(_asset, fit: BoxFit.contain, repeat: true),
      ),
    );
  }
}

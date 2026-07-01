import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/material.dart';

import 'brand_loader.dart';

/// Pull-to-refresh with the MyWeli `mark_loader` instead of the Material spinner.
/// Drop-in for [RefreshIndicator] — same `onRefresh` + `child`. Design:
/// docs/design/branding-integration.md.
class BrandRefresh extends StatelessWidget {
  const BrandRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomMaterialIndicator(
      onRefresh: onRefresh,
      indicatorBuilder: (context, controller) =>
          const BrandLoader(size: 24, fast: true),
      child: child,
    );
  }
}

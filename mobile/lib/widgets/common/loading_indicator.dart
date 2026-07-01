import 'package:flutter/material.dart';

import 'brand_loader.dart';

/// App-wide loading indicator — renders the MyWeli brand loader (`mark_loader`)
/// so every loading / refresh state is on-brand. Keeps the original API: [size]
/// sets the box; a light [color] hint selects the white cut (for dark
/// backgrounds). Design: docs/design/branding-integration.md.
class LoadingIndicator extends StatelessWidget {
  final Color? color;
  final double? size;

  const LoadingIndicator({
    super.key,
    this.color,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    final onDark = color != null && color!.computeLuminance() > 0.5;
    return BrandLoader(size: size ?? 40, onDark: onDark);
  }
}

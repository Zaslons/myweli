import 'dart:async';

import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/theme/app_theme.dart';
import 'brand_loader.dart';

/// Pull-to-refresh with the MyWeli `mark_loader` instead of the Material spinner.
/// Drop-in for [RefreshIndicator] — same `onRefresh` + `child`. Design:
/// docs/design/branding-integration.md.
class BrandRefresh extends StatelessWidget {
  const BrandRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.announce = 'Liste mise à jour',
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// The message a screen reader speaks once the refresh completes — the
  /// reloaded list is off-focus, so an announcement voices the result. Defaults
  /// to a generic "Liste mise à jour" so *every* pull-to-refresh confirms; pass a
  /// screen-specific French string to override, or `null` to stay silent.
  final String? announce;

  @override
  Widget build(BuildContext context) {
    // Capture the view + reading direction before the async gap — the build
    // context must not be used after the `await` inside the refresh wrapper.
    final view = View.of(context);
    final textDirection = Directionality.of(context);
    return CustomMaterialIndicator(
      onRefresh: () async {
        await onRefresh();
        if (announce != null) {
          unawaited(
            SemanticsService.sendAnnouncement(view, announce!, textDirection),
          );
        }
      },
      indicatorBuilder: (context, controller) =>
          const BrandLoader(size: AppTheme.iconM, fast: true),
      child: child,
    );
  }
}

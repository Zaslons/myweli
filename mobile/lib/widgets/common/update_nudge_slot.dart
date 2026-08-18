import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/version/client_version_gate.dart';
import 'update_available_banner.dart';

/// Renders the update nudge, or nothing.
///
/// **One widget, mounted on both home surfaces**, so the "should this show?"
/// rule lives in one place rather than being re-derived per app. It resolves
/// three conditions: the server recommended an update, we have somewhere to
/// send the user, and they have not already dismissed *this* recommendation.
///
/// Renders `SizedBox.shrink()` in every other case — including while the
/// dismissal preference is still loading, so the banner never flashes in and
/// straight back out on a surface the user is already reading.
class UpdateNudgeSlot extends StatelessWidget {
  const UpdateNudgeSlot({super.key, this.result});

  /// Test seam; production reads the value `main()` published.
  final ClientVersionResult? result;

  @override
  Widget build(BuildContext context) {
    final r = result ?? clientVersionResult;
    final url = r.updateUrl;
    if (r.verdict != ClientVersionVerdict.updateAvailable || url == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<bool>(
      future: UpdateAvailableBanner.shouldShow(r.build),
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
          child: UpdateAvailableBanner(
            updateUrl: url,
            recommendedBuild: r.build,
          ),
        );
      },
    );
  }
}

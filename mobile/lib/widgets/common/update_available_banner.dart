import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/external_link.dart';
import 'app_button.dart';

/// The gentle half of the version gate: a newer build is recommended, but this
/// one still works (docs/design/client-version-gate.md §8.2).
///
/// **Dismissible, and that is the whole difference from the blocking screen.**
/// A nudge that cannot be dismissed is just a block with extra steps, and it
/// would train people to ignore the one that matters.
///
/// **Dismissal is remembered per recommended build**, not once and forever: the
/// next recommendation is a new fact and deserves to be shown again, while
/// re-launching today does not re-nag. Stored in `shared_preferences` rather
/// than secure storage — this is a UI preference, not a secret, and putting it
/// in the keychain would make it survive a reinstall, which is the opposite of
/// what anyone wants.
///
/// Follows `PushBlockedBanner`'s shape: state the fact, name the action the
/// user takes outside the app.
class UpdateAvailableBanner extends StatefulWidget {
  const UpdateAvailableBanner({
    super.key,
    required this.updateUrl,
    required this.recommendedBuild,
    this.onOpen,
  });

  final String updateUrl;

  /// Which recommendation this is. Dismissal is keyed on it.
  final int recommendedBuild;

  /// Test seam, mirroring `PushBlockedBanner.onOpenSettings`.
  final void Function(BuildContext, String)? onOpen;

  static String prefsKey(int build) => 'update_nudge_dismissed_$build';

  /// Whether the banner should be shown at all for [recommendedBuild].
  static Future<bool> shouldShow(int recommendedBuild) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(prefsKey(recommendedBuild)) ?? false);
  }

  @override
  State<UpdateAvailableBanner> createState() => _UpdateAvailableBannerState();
}

class _UpdateAvailableBannerState extends State<UpdateAvailableBanner> {
  bool _dismissed = false;

  Future<void> _dismiss() async {
    setState(() => _dismissed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      UpdateAvailableBanner.prefsKey(widget.recommendedBuild),
      true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final open = widget.onOpen ?? openExternalUrl;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingM),
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.system_update_outlined,
                size: AppTheme.iconS,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppTheme.spacingS),
              Expanded(
                child: Text(
                  'Une nouvelle version est disponible',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              // Icon-only, so it carries a tooltip (SYSTEM.md §13.4) and keeps
              // the 48-dp target `IconButton` gives it by default.
              IconButton(
                icon: const Icon(Icons.close, size: AppTheme.iconS),
                tooltip: 'Masquer',
                color: AppColors.textSecondary,
                onPressed: _dismiss,
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingXS),
          Text(
            'Mettez à jour MyWeli pour profiter des dernières améliorations.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
          AppButton(
            text: 'Mettre à jour',
            type: AppButtonType.secondary,
            onPressed: () => open(context, widget.updateUrl),
          ),
        ],
      ),
    );
  }
}

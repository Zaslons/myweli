import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

/// A row in a settings list.
///
/// Promoted from `profile_screen.dart`'s private `_SettingsItem` (L1) so the new
/// « À propos » screen renders rows identical to the profile it opens from —
/// two hand-written copies would have drifted the first time either was touched.
///
/// The pro profile is deliberately **not** converted: its thirteen rows are
/// hand-written `Card { ListTile }`s in a different visual idiom, and unifying
/// them is a refactor that does not belong in a store-submission change.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Replaces the chevron. Supplying one on a row that also has [onTap] hides
  /// the affordance — which is how « À propos » came to look tappable while
  /// carrying no handler at all.
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.textPrimary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: AppTextStyles.bodyLarge.copyWith(color: color)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
      trailing:
          trailing ??
          const Icon(Icons.chevron_right, color: AppColors.textTertiary),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingM,
        vertical: AppTheme.spacingS,
      ),
    );
  }
}

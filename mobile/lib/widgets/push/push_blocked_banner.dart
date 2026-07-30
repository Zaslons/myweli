import 'package:flutter/material.dart';

import '../../core/push/system_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../common/app_button.dart';

/// Shown when notifications are DENIED at the OS level — the one dead end the
/// app cannot fix from the inside: no in-app toggle can re-enable them, only
/// the system settings can. Without this, a user who once tapped « Refuser »
/// would silently never hear from us again, and the push toggle above would
/// lie to them.
///
/// Design: docs/design/push-notifications-app.md.
class PushBlockedBanner extends StatelessWidget {
  const PushBlockedBanner({
    super.key,
    this.onOpenSettings = openSystemNotificationSettings,
  });

  /// Test seam (the default opens the OS settings).
  final SettingsOpener onOpenSettings;

  @override
  Widget build(BuildContext context) {
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
                Icons.notifications_off_outlined,
                size: AppTheme.iconS,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppTheme.spacingS),
              Expanded(
                child: Text(
                  'Notifications désactivées pour l’appareil',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingXS),
          Text(
            'Autorisez Myweli dans les réglages de votre téléphone pour '
            'recevoir vos rappels et confirmations.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
          AppButton(
            text: 'Ouvrir les réglages',
            type: AppButtonType.secondary,
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

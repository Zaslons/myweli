import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../common/app_button.dart';

/// Shown when this phone was never asked for notifications — after « Plus
/// tard », or before any booking (consumer-signin-push.md §2.9, decision 209).
/// Its button shows the system prompt directly: the card is the explanation.
///
/// The twin of `PushBlockedBanner` (the system said no: only Settings can
/// change it): the same shape, but nothing is wrong yet — `notifications_none`
/// in `textPrimary`, not the banner's `warning`.
///
/// Before it, an iPhone whose owner chose « Plus tard » could never receive a
/// push: iOS shows no switch in Settings for an app that never asked, and
/// Préférences said nothing.
class PushOffCard extends StatelessWidget {
  const PushOffCard({
    super.key,
    required this.onEnable,
    this.body = clientBody,
    this.busy = false,
  });

  /// The client's reason: reminders and the salon's answer.
  static const String clientBody =
      'Activez-les pour recevoir vos rappels et la réponse de votre salon.';

  /// MyWeli Pro's reason (decision 212): a salon's four events
  /// (`PushBlockedBanner`'s Pro sentence, promise-honesty-sweep.md T4).
  static const String proBody =
      'Activez-les pour être prévenu·e des réservations, reports, '
      'annulations et acomptes de vos clients.';

  /// « Activer les notifications »: the system prompt.
  final VoidCallback onEnable;

  final String body;

  /// The system prompt is open: the button waits.
  final bool busy;

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
            // The icon stays with the title's FIRST line when the title wraps
            // (200 % text: three lines) — as Préférences' info line does;
            // centred, it floated beside the middle line.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.notifications_none,
                size: AppTheme.iconS,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: AppTheme.spacingS),
              Expanded(
                child: Text(
                  'Notifications non activées sur ce téléphone',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingXS),
          Text(
            body,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
          AppButton(
            text: 'Activer les notifications',
            type: AppButtonType.secondary,
            isLoading: busy,
            onPressed: busy ? null : onEnable,
          ),
        ],
      ),
    );
  }
}

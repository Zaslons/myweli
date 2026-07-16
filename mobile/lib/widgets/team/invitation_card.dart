import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../models/team_invitation.dart';
import '../common/app_button.dart';

/// « {Salon} vous invite comme {Rôle} » — shared by the login
/// « Invitations » step and the authed Profil → Invitations screen
/// (module `access` R3 §2.2/§2.3).
class InvitationCard extends StatelessWidget {
  const InvitationCard({
    super.key,
    required this.invitation,
    required this.onAccept,
    required this.onDecline,
    this.busy = false,
  });

  final TeamInvitation invitation;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: AppColors.surfaceVariant,
                      child: Icon(Icons.storefront_outlined,
                          color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: AppTheme.spacingM),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: AppTextStyles.bodyLarge,
                          children: [
                            TextSpan(
                              text: invitation.salonName,
                              style: AppTextStyles.titleMedium,
                            ),
                            const TextSpan(text: ' vous invite comme '),
                            TextSpan(
                              text: invitation.roleLabel,
                              style: AppTextStyles.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (invitation.expiresAt != null) ...[
                  const SizedBox(height: AppTheme.spacingS),
                  Text(
                    'Expire le ${Formatters.formatDate(invitation.expiresAt!)}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  text: 'Rejoindre',
                  isLoading: busy,
                  onPressed: busy ? null : onAccept,
                ),
              ),
              const SizedBox(width: AppTheme.spacingM),
              AppButton(
                text: 'Refuser',
                type: AppButtonType.text,
                onPressed: busy ? null : onDecline,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

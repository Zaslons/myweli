import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_notification.dart';

/// A single notification row, styled to match the app's other list tiles
/// (white card, rounded, leading icon square). Unread items show a bold title
/// and a dot.
class NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
  });

  IconData _iconFor(AppNotificationType type) {
    switch (type) {
      case AppNotificationType.bookingConfirmed:
        return Icons.check_circle_outline;
      case AppNotificationType.depositReceived:
        return Icons.account_balance_wallet_outlined;
      case AppNotificationType.reminder:
        return Icons.alarm;
      case AppNotificationType.reschedule:
        return Icons.event_repeat;
      case AppNotificationType.cancellation:
        return Icons.cancel_outlined;
      case AppNotificationType.reviewRequest:
        return Icons.star_outline;
      case AppNotificationType.general:
        return Icons.notifications_none;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = !notification.read;
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        child: Container(
          padding: const EdgeInsets.all(AppTheme.spacingM),
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
            boxShadow: AppTheme.elevation1,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (unread) Semantics(label: 'Non lu'),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
                child: Icon(
                  _iconFor(notification.type),
                  size: AppTheme.iconS,
                  color:
                      unread ? AppColors.textPrimary : AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: AppTheme.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: unread
                                ? AppTextStyles.titleSmall
                                    .copyWith(color: AppColors.textPrimary)
                                : AppTextStyles.bodyMedium
                                    .copyWith(color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingS),
                        Text(
                          Formatters.formatRelative(notification.createdAt),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: AppTheme.spacingS),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacingXS),
                    Text(
                      notification.body,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

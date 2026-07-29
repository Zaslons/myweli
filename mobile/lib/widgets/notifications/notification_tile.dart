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
                    // A12 — **this is the defect `expectNoLegibilityCrush` was
                    // built for**, and it is named in the primitive's own
                    // docstring and in §21 row 68. The census re-measured it
                    // (~86dp of a 240dp row, not row 68's ~30dp) and then the
                    // slice fixed everything around it and left this alone; the
                    // adversarial review caught that the register row was about
                    // to be closed over a defect still shipping.
                    //
                    // The mechanism is the crush: the title is flexed, the
                    // timestamp beside it is not, so « Rendez-vous confirmé »
                    // spends its declared ellipsis on a squeeze it did not
                    // choose — and a DECLARED ellipsis is exactly what
                    // `expectNoUndeclaredTruncation` skips by design.
                    //
                    // `Wrap`, the same answer as `ReviewTile`, `SectionHeading`,
                    // `CompactAppointmentTile` and `AppointmentCard`. The
                    // timestamp and its unread dot are ONE child, so a wrap
                    // never separates a time from the dot that qualifies it.
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppTheme.spacingS,
                        runSpacing: AppTheme.spacingXS,
                        children: [
                          Text(
                            notification.title,
                            style: unread
                                ? AppTextStyles.titleSmall
                                    .copyWith(color: AppColors.textPrimary)
                                : AppTextStyles.bodyMedium
                                    .copyWith(color: AppColors.textSecondary),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                Formatters.formatRelative(
                                    notification.createdAt),
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
                        ],
                      ),
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

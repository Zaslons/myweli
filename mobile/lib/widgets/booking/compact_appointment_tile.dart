import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../models/appointment.dart';
import '../common/timed_cached_image.dart';

class CompactAppointmentTile extends StatelessWidget {
  final Appointment appointment;
  final String providerName;
  final String? providerImageUrl;
  final VoidCallback onTap;

  /// Optional hint shown under the date (e.g. "Réserver à nouveau" on a past
  /// appointment whose tap rebooks).
  final String? hint;

  const CompactAppointmentTile({
    super.key,
    required this.appointment,
    required this.providerName,
    required this.onTap,
    this.providerImageUrl,
    this.hint,
  });

  Color _statusColor(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return AppColors.warningLight;
      case AppointmentStatus.confirmed:
        return AppColors.successLight;
      case AppointmentStatus.completed:
        return AppColors.infoLight;
      case AppointmentStatus.cancelled:
        return AppColors.errorLight;
      case AppointmentStatus.noShow:
        return AppColors.warningLight;
    }
  }

  String _statusText(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return 'En attente';
      case AppointmentStatus.confirmed:
        return 'Confirmé';
      case AppointmentStatus.completed:
        return 'Terminé';
      case AppointmentStatus.cancelled:
        return 'Annulé';
      case AppointmentStatus.noShow:
        return 'Absent';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(appointment.status);

    return InkWell(
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
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              child: (providerImageUrl != null && providerImageUrl!.isNotEmpty)
                  ? TimedCachedImage(
                      imageUrl: providerImageUrl!,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 52,
                      height: 52,
                      color: AppColors.surface,
                      child: const Icon(
                        Icons.store_outlined,
                        color: AppColors.textTertiary,
                      ),
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
                          providerName,
                          style: AppTextStyles.titleSmall.copyWith(
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _statusText(appointment.status),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${Formatters.formatDateShort(appointment.appointmentDate)} • ${Formatters.formatTime(appointment.appointmentDate)}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.refresh,
                            size: 14, color: AppColors.textPrimary),
                        const SizedBox(width: 4),
                        Text(
                          hint!,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacingS),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

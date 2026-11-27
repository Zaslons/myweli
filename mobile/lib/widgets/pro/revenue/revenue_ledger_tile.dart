import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/revenue_wording.dart';
import '../../../core/utils/salon_id.dart';
import '../../../core/utils/salon_time.dart';
import '../../../models/revenue_analytics.dart';
import '../../common/app_card.dart';
import '../../common/label_value_row.dart';

/// One booking behind a figure (docs/design/pro-revenue-analytics.md §4.9):
/// its date and time in salon time, its amount in its own currency, then
/// « {client} · {prestations} · {collaborateur} ». Under a prestation's
/// filter the amount is that prestation's line, with « sur {total} » under
/// it. The whole card opens the booking — `/pro/appointment/:id?salon=`,
/// which switches salon first when it must.
class RevenueLedgerTile extends StatelessWidget {
  const RevenueLedgerTile({
    super.key,
    required this.row,
    required this.salonId,
    required this.timezone,
    this.onReturn,
  });

  final RevenueLedgerRow row;
  final SalonId salonId;

  /// The salon's zone, from the answer.
  final String timezone;

  /// Called when the booking's screen closes — the figures may have moved
  /// (« Terminé », « Absent »).
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final at = toSalonTime(row.appointmentDate, tz: timezone);
    final when =
        '${Formatters.formatWeekdayDayMonthShort(at)} · '
        '${Formatters.formatTime(at)}';
    String money(double v) =>
        Formatters.formatCurrency(v, currency: row.currency);
    final amount = row.estimated
        ? '${money(row.amount)} · estimé'
        : money(row.amount);
    return AppCard(
      onTap: () async {
        await context.push(
          Uri(
            path: '/pro/appointment/${row.appointmentId}',
            queryParameters: {'salon': '$salonId'},
          ).toString(),
        );
        onReturn?.call();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabelValueRow(
            label: when,
            value: amount,
            labelStyle: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            valueStyle: AppTextStyles.titleSmall.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          if (row.amount != row.totalPrice)
            Text(
              'sur ${money(row.totalPrice)}',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          const SizedBox(height: AppTheme.spacingXS),
          Text(
            revenueLedgerLine(row),
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

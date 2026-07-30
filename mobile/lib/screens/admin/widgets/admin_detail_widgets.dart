import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/timed_cached_image.dart';
import 'status_chip.dart';

/// Shared building blocks for the admin support views (salon / client detail).
/// Design: docs/design/admin-console-ui.md §3.

/// A titled profile card: entity name + status chip, then label/value rows.
class AdminProfileCard extends StatelessWidget {
  const AdminProfileCard({
    super.key,
    required this.title,
    required this.status,
    required this.rows,
  });

  final String title;
  final String status;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTextStyles.titleMedium)),
              StatusChip.forStatus(status),
            ],
          ),
          const SizedBox(height: AppTheme.spacingM),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacingSM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textTertiary)),
                  Text(value, style: AppTextStyles.bodyMedium),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Derniers rendez-vous" — a compact table of an entity's recent appointments
/// (date · statut · montant · client). Empty state included.
class AdminBookingsCard extends StatelessWidget {
  const AdminBookingsCard({super.key, required this.items, this.onOpenDispute});

  final List<Map<String, dynamic>> items;

  /// When set, each row shows an "Ouvrir un litige" action carrying the
  /// appointment id (the support-view → dispute-creation entry point).
  final void Function(String appointmentId)? onOpenDispute;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Derniers rendez-vous', style: AppTextStyles.titleSmall),
        const SizedBox(height: AppTheme.spacingS),
        if (items.isEmpty)
          Text('Aucun rendez-vous.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textTertiary))
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  _row(items[i], last: i == items.length - 1),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(Map<String, dynamic> a, {required bool last}) {
    final date = DateTime.tryParse('${a['appointmentDate'] ?? ''}');
    final price = a['totalPrice'] as num?;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingM, vertical: AppTheme.spacingSM),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              date == null ? '—' : Formatters.formatDateShort(date),
              style: AppTextStyles.bodyMedium,
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusChip.forStatus('${a['status'] ?? ''}'),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              // Platform console — platform currency by design (multi-pays).
              price == null ? '—' : Formatters.formatCurrency(price.toDouble()),
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${a['clientName'] ?? '—'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          if (onOpenDispute != null)
            SizedBox(
              width: 40,
              child: IconButton(
                tooltip: 'Ouvrir un litige',
                icon: const Icon(Icons.gavel_outlined, size: AppTheme.iconS),
                onPressed: () => onOpenDispute!('${a['id']}'),
              ),
            ),
        ],
      ),
    );
  }
}

/// A signed-URL evidence image (deposit screenshot), tap to zoom. Used by the
/// dispute detail. Shows a neutral placeholder when there's no URL.
class AdminEvidenceImage extends StatelessWidget {
  const AdminEvidenceImage({super.key, required this.url, this.caption});

  final String? url;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (caption != null) ...[
          Text(caption!, style: AppTextStyles.titleSmall),
          const SizedBox(height: AppTheme.spacingS),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: SizedBox(
            width: 240,
            height: 260,
            child: url == null
                ? const ColoredBox(
                    color: AppColors.surfaceVariant,
                    child: Center(
                      child: Icon(Icons.receipt_long_outlined,
                          color: AppColors.textTertiary),
                    ),
                  )
                : GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        backgroundColor: Colors.transparent,
                        child: InteractiveViewer(
                          child: TimedCachedImage(
                            imageUrl: url!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    child: TimedCachedImage(imageUrl: url!, fit: BoxFit.cover),
                  ),
          ),
        ),
      ],
    );
  }
}

/// The sticky bottom action bar shared by the support views.
class AdminActionBar extends StatelessWidget {
  const AdminActionBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: const BoxDecoration(
        color: AppColors.secondary,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: children),
    );
  }
}

/// Centered error + retry for a detail screen that failed to load.
class AdminDetailError extends StatelessWidget {
  const AdminDetailError(
      {super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: AppTextStyles.bodyMedium),
          const SizedBox(height: AppTheme.spacingM),
          SizedBox(
            width: 160,
            child: AppButton(
              text: 'Réessayer',
              type: AppButtonType.secondary,
              onPressed: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

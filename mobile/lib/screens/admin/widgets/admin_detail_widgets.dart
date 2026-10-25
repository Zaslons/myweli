import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/text_fit.dart';
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
                  Text(
                    label,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
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
          Text(
            'Aucun rendez-vous.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          )
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
    final dateText = date == null ? '—' : Formatters.formatDateShort(date);
    // Platform console — platform currency by design (multi-pays).
    final priceText = price == null
        ? '—'
        : Formatters.formatCurrency(price.toDouble());
    final muted = AppTextStyles.bodyMedium.copyWith(
      color: AppColors.textSecondary,
    );
    final dateCell = Text(dateText, style: AppTextStyles.bodyMedium);
    final statusCell = Align(
      alignment: Alignment.centerLeft,
      child: StatusChip.forStatus('${a['status'] ?? ''}'),
    );
    final priceCell = Text(priceText, style: muted);
    final clientCell = Text(
      '${a['clientName'] ?? '—'}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: muted,
    );
    final dispute = onOpenDispute == null
        ? null
        : SizedBox(
            width: _disputeWidth,
            child: IconButton(
              tooltip: 'Ouvrir un litige',
              icon: const Icon(Icons.gavel_outlined, size: AppTheme.iconS),
              onPressed: () => onOpenDispute!('${a['id']}'),
            ),
          );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingM,
        vertical: AppTheme.spacingSM,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      // One line, in fixed shares (date 3 · status 2 · price 2 · client 3),
      // while the date and the price fit theirs; else two lines — date and
      // status, then price and client — each line in halves (B7.10, SYSTEM
      // §21 row 96). A seven-digit price broke inside its 2-in-10 share at
      // 600 dp and 200 % text. Measured with [TextFit], never a constant.
      child: LayoutBuilder(
        builder: (context, box) {
          final fit = TextFit.of(context);
          final share =
              (box.maxWidth - (dispute == null ? 0 : _disputeWidth)) / 10;
          final oneLine =
              fit.holds(share * 3, [
                (text: dateText, style: AppTextStyles.bodyMedium),
              ]) &&
              fit.holds(share * 2, [(text: priceText, style: muted)]);
          if (oneLine) {
            return Row(
              children: [
                Expanded(flex: 3, child: dateCell),
                Expanded(flex: 2, child: statusCell),
                Expanded(flex: 2, child: priceCell),
                Expanded(flex: 3, child: clientCell),
                ?dispute,
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: dateCell),
                        Expanded(child: statusCell),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacingXS),
                    Row(
                      children: [
                        Expanded(child: priceCell),
                        Expanded(child: clientCell),
                      ],
                    ),
                  ],
                ),
              ),
              ?dispute,
            ],
          );
        },
      ),
    );
  }

  /// The « Ouvrir un litige » action's slot.
  static const double _disputeWidth = 40;
}

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
                      child: Icon(
                        Icons.receipt_long_outlined,
                        color: AppColors.textTertiary,
                      ),
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

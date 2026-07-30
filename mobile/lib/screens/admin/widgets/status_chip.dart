import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/status_labels.dart';

/// Semantic meaning of a status pill.
enum AdminChipKind { ok, pending, danger, neutral }

/// A status pill in the app's semantic palette (light tint + dark text).
/// Design: docs/design/admin-console-ui.md §2.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.kind});

  final String label;
  final AdminChipKind kind;

  /// Maps a backend status string to a chip (verified/active → ok, pending/open
  /// → pending, suspended/banned/rejected/hidden → danger).
  factory StatusChip.forStatus(String? status) {
    final s = (status ?? '').toLowerCase();
    final kind = switch (s) {
      'verified' || 'active' || 'confirmed' || 'resolved' => AdminChipKind.ok,
      'pending' || 'open' => AdminChipKind.pending,
      'rejected' ||
      'suspended' ||
      'banned' ||
      'hidden' ||
      'cancelled' ||
      'noshow' => AdminChipKind.danger,
      _ => AdminChipKind.neutral,
    };
    // A9: `StatusLabels.ofRaw` is normalisation-robust like the kind switch
    // above — `NO_SHOW`/`noShow`/`no-show` are one status. `_frenchLabel` fell
    // through to `raw`, so `confirmed`, `cancelled`, `completed` and `noShow`
    // printed the ENGLISH ENUM beside a correctly-tinted pill; `pending` also
    // rendered lowercase while the rest of the app capitalised it. `—` on an
    // unknown status rather than the wire value: that fallback IS how English
    // reached a user.
    return StatusChip(label: StatusLabels.ofRaw(status) ?? '—', kind: kind);
  }

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (kind) {
      AdminChipKind.ok => (
        AppColors.success,
        AppColors.success.withValues(alpha: 0.12),
      ),
      AdminChipKind.pending => (
        AppColors.warning,
        AppColors.warning.withValues(alpha: 0.14),
      ),
      AdminChipKind.danger => (
        AppColors.error,
        AppColors.error.withValues(alpha: 0.12),
      ),
      AdminChipKind.neutral => (
        AppColors.textSecondary,
        AppColors.surfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingSM,
        vertical: AppTheme.spacingXS,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(label, style: AppTextStyles.bodySmall.copyWith(color: fg)),
    );
  }
}

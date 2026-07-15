import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';

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
      'noshow' =>
        AdminChipKind.danger,
      _ => AdminChipKind.neutral,
    };
    return StatusChip(label: _frenchLabel(s, status), kind: kind);
  }

  static String _frenchLabel(String s, String? raw) => switch (s) {
        'verified' => 'vérifié',
        'active' => 'actif',
        'pending' => 'en attente',
        'rejected' => 'rejeté',
        'suspended' => 'suspendu',
        'banned' => 'banni',
        'hidden' => 'masqué',
        'open' => 'ouvert',
        'resolved' => 'résolu',
        _ => raw ?? '—',
      };

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (kind) {
      AdminChipKind.ok => (
          AppColors.success,
          AppColors.success.withValues(alpha: 0.12)
        ),
      AdminChipKind.pending => (
          AppColors.warning,
          AppColors.warning.withValues(alpha: 0.14)
        ),
      AdminChipKind.danger => (
          AppColors.error,
          AppColors.error.withValues(alpha: 0.12)
        ),
      AdminChipKind.neutral => (
          AppColors.textSecondary,
          AppColors.surfaceVariant
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingSM, vertical: AppTheme.spacingXS),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(color: fg),
      ),
    );
  }
}

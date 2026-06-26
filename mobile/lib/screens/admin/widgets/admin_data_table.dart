import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/empty_state.dart';

class AdminColumn {
  const AdminColumn(this.label, {this.flex = 1});
  final String label;
  final int flex;
}

class AdminRow {
  const AdminRow({required this.cells, this.onTap});
  final List<Widget> cells;
  final VoidCallback? onTap;
}

/// The admin queue table: header + comfortable (~52px) rows with hover + tap,
/// and built-in loading (skeleton) / empty / error states.
/// Design: docs/design/admin-console-ui.md §2.
class AdminDataTable extends StatelessWidget {
  const AdminDataTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.emptyTitle,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyDescription,
    this.isLoading = false,
    this.error,
    this.onRetry,
  });

  final List<AdminColumn> columns;
  final List<AdminRow> rows;
  final String emptyTitle;
  final IconData emptyIcon;
  final String? emptyDescription;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerRow(),
          const Divider(height: 1, color: AppColors.divider),
          _body(),
        ],
      ),
    );
  }

  Widget _headerRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          for (final c in columns)
            Expanded(
              flex: c.flex,
              child: Text(
                c.label,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (isLoading && rows.isEmpty) {
      return Column(
        children: List.generate(4, (_) => _skeletonRow()),
      );
    }
    if (error != null && rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        child: Column(
          children: [
            Text(error!, style: AppTextStyles.bodyMedium),
            const SizedBox(height: AppTheme.spacingM),
            if (onRetry != null)
              AppButton(
                text: 'Réessayer',
                type: AppButtonType.secondary,
                onPressed: onRetry,
              ),
          ],
        ),
      );
    }
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXL),
        child: EmptyState(
          icon: emptyIcon,
          title: emptyTitle,
          description: emptyDescription,
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: AppColors.divider),
          _dataRow(rows[i]),
        ],
      ],
    );
  }

  Widget _dataRow(AdminRow row) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: row.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              for (var c = 0; c < columns.length; c++)
                Expanded(
                  flex: columns[c].flex,
                  child: c < row.cells.length
                      ? row.cells[c]
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skeletonRow() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
      ),
    );
  }
}

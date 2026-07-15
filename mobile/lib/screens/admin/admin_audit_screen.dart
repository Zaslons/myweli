import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../providers/admin/admin_audit_provider.dart';
import 'widgets/admin_data_table.dart';
import 'widgets/admin_scaffold.dart';
import 'widgets/audit_actions.dart';

/// The append-only admin audit log ("Journal"): read-only, filterable by action,
/// paginated. Design: docs/design/admin-console-ui.md §3.
class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key});

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AdminAuditProvider>().load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminAuditProvider>();
    return AdminScaffold(
      title: 'Journal',
      actions: [_ActionFilter(value: p.action)],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminDataTable(
              isLoading: p.isLoading,
              error: p.error,
              onRetry: () => context.read<AdminAuditProvider>().load(),
              emptyIcon: Icons.history,
              emptyTitle: 'Aucune entrée',
              emptyDescription: 'Aucune action ne correspond à ce filtre.',
              columns: const [
                AdminColumn('Quand', flex: 3),
                AdminColumn('Action', flex: 3),
                AdminColumn('Cible', flex: 3),
                AdminColumn('Motif', flex: 3),
                AdminColumn('Acteur', flex: 2),
              ],
              rows: [
                for (final e in p.items)
                  AdminRow(
                    cells: [
                      Text(_when(e['createdAt']),
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textSecondary)),
                      Text(auditActionLabel(e['action'] as String?),
                          style: AppTextStyles.bodyMedium),
                      Text(_target(e),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textSecondary)),
                      Text('${e['reason'] ?? '—'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textSecondary)),
                      Text('${e['actorAdminId'] ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
              ],
            ),
            if (!p.isLoading && p.error == null && p.items.isNotEmpty)
              _Pager(provider: p),
          ],
        ),
      ),
    );
  }

  String _when(Object? raw) {
    final d = DateTime.tryParse('${raw ?? ''}');
    if (d == null) return '—';
    // Device time ON PURPOSE — the internal ops console reads audit stamps
    // in the operator's own zone (docs/design/timezone-salon-time.md §2);
    // this is the grep-pin allowlist's single `.toLocal()` exception.
    final local = d.toLocal();
    return '${Formatters.formatDateShort(local)} ${Formatters.formatTime(local)}';
  }

  String _target(Map<String, dynamic> e) {
    final type = e['targetType'];
    final id = e['targetId'];
    if (type == null && id == null) return '—';
    return '${type ?? '—'} · ${id ?? '—'}';
  }
}

class _ActionFilter extends StatelessWidget {
  const _ActionFilter({required this.value});
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          style: AppTextStyles.bodyMedium,
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
          items: [
            const DropdownMenuItem(
                value: null, child: Text('Toutes les actions')),
            for (final entry in kAuditActions.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (v) => context.read<AdminAuditProvider>().setAction(v),
        ),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({required this.provider});
  final AdminAuditProvider provider;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacingM),
      child: Row(
        children: [
          Text('${provider.total} entrée(s)',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textTertiary)),
          const Spacer(),
          IconButton(
            tooltip: 'Précédent',
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: provider.hasPrev
                ? () => context.read<AdminAuditProvider>().prevPage()
                : null,
          ),
          Text('Page ${provider.page}', style: AppTextStyles.bodyMedium),
          IconButton(
            tooltip: 'Suivant',
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: provider.hasNext
                ? () => context.read<AdminAuditProvider>().nextPage()
                : null,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../providers/admin/admin_disputes_provider.dart';
import 'widgets/admin_data_table.dart';
import 'widgets/admin_scaffold.dart';
import 'widgets/admin_segmented_control.dart';
import 'widgets/status_chip.dart';

/// Dispute cases: filter (Ouverts / Résolus / Tous) + table → detail.
/// Design: docs/design/admin-console-ui.md §3.
class AdminDisputesScreen extends StatefulWidget {
  const AdminDisputesScreen({super.key});

  @override
  State<AdminDisputesScreen> createState() => _AdminDisputesScreenState();
}

class _AdminDisputesScreenState extends State<AdminDisputesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AdminDisputesProvider>().load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminDisputesProvider>();
    return AdminScaffold(
      title: 'Litiges',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminSegmentedControl(
              labels: const ['Ouverts', 'Résolus', 'Tous'],
              selected: p.filter,
              onSelect: (i) =>
                  context.read<AdminDisputesProvider>().setFilter(i),
            ),
            const SizedBox(height: AppTheme.spacingM),
            AdminDataTable(
              isLoading: p.isLoading,
              error: p.error,
              onRetry: () => context.read<AdminDisputesProvider>().load(),
              emptyIcon: Icons.gavel_outlined,
              emptyTitle: 'Aucun litige',
              emptyDescription:
                  'Ouvrez un litige depuis une réservation (fiche salon/client).',
              columns: const [
                AdminColumn('Motif', flex: 4),
                AdminColumn('Statut', flex: 2),
                AdminColumn('Ouvert le', flex: 2),
              ],
              rows: [
                for (final d in p.items)
                  AdminRow(
                    onTap: () => context.push('/admin/disputes/${d['id']}'),
                    cells: [
                      Text(
                        '${d['reason'] ?? '—'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium,
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: StatusChip.forStatus('${d['status'] ?? 'open'}'),
                      ),
                      Text(
                        _date(d['createdAt']),
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _date(Object? raw) {
    final d = DateTime.tryParse('${raw ?? ''}');
    return d == null ? '—' : Formatters.formatDateShort(d);
  }
}

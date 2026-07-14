import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/admin/admin_providers_provider.dart';
import '../../widgets/common/app_button.dart';
import 'widgets/admin_data_table.dart';
import 'widgets/admin_scaffold.dart';
import 'widgets/admin_search_field.dart';
import 'widgets/admin_segmented_control.dart';
import 'widgets/reason_dialog.dart';
import 'widgets/status_chip.dart';

/// Salon (provider) management: filter + search + suspend/restore + featured.
/// Design: docs/design/admin-console-ui.md §3.
class AdminProvidersScreen extends StatefulWidget {
  const AdminProvidersScreen({super.key});

  @override
  State<AdminProvidersScreen> createState() => _AdminProvidersScreenState();
}

class _AdminProvidersScreenState extends State<AdminProvidersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AdminProvidersProvider>().load(),
    );
  }

  Future<void> _suspend(String id) async {
    final reason = await showReasonDialog(
      context,
      title: 'Suspendre ce salon ?',
      confirmLabel: 'Suspendre',
      hint: 'Motif (interne)',
      reasonRequired: false,
    );
    if (reason == null || !mounted) return;
    await _run(() => context.read<AdminProvidersProvider>().suspend(id, reason),
        'Salon suspendu');
  }

  Future<void> _restore(String id) => _run(
      () => context.read<AdminProvidersProvider>().restore(id),
      'Salon réactivé');

  Future<void> _feature(String id, bool featured) => _run(
      () => context.read<AdminProvidersProvider>().feature(id, featured),
      featured ? 'Mis en avant' : 'Retiré de la mise en avant');

  Future<void> _run(Future<bool> Function() action, String okMsg) async {
    final p = context.read<AdminProvidersProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await action();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? okMsg : (p.actionError ?? 'Échec'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminProvidersProvider>();
    return AdminScaffold(
      title: 'Salons',
      actions: [
        AdminSearchField(
          hint: 'Rechercher un salon…',
          onSubmitted: (q) => context.read<AdminProvidersProvider>().search(q),
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminSegmentedControl(
              labels: const ['Tous', 'Actifs', 'Suspendus'],
              selected: p.filter,
              onSelect: (i) =>
                  context.read<AdminProvidersProvider>().setFilter(i),
            ),
            const SizedBox(height: AppTheme.spacingM),
            AdminDataTable(
              isLoading: p.isLoading,
              error: p.error,
              onRetry: () => context.read<AdminProvidersProvider>().load(),
              emptyIcon: Icons.storefront_outlined,
              emptyTitle: 'Aucun salon',
              emptyDescription: 'Aucun salon ne correspond à ce filtre.',
              columns: const [
                AdminColumn('Salon', flex: 3),
                AdminColumn('Commune', flex: 2),
                AdminColumn('Statut', flex: 2),
                AdminColumn('Note', flex: 1),
                AdminColumn('Action', flex: 3),
              ],
              rows: [
                for (final r in p.items)
                  AdminRow(
                    onTap: () => context.push('/admin/providers/${r['id']}'),
                    cells: [
                      Text('${r['name'] ?? '—'}',
                          style: AppTextStyles.bodyMedium),
                      Text('${r['commune'] ?? '—'}',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textSecondary)),
                      Align(
                        alignment: Alignment.centerLeft,
                        child:
                            StatusChip.forStatus('${r['status'] ?? 'active'}'),
                      ),
                      Text((r['rating'] as num?)?.toStringAsFixed(1) ?? '—',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textSecondary)),
                      _actions(r, p.acting),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actions(Map<String, dynamic> r, bool acting) {
    final id = '${r['id']}';
    final featured = r['featured'] == true;
    final suspended = r['status'] == 'suspended';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          tooltip: featured ? 'Retirer la mise en avant' : 'Mettre en avant',
          icon: Icon(
            featured ? Icons.star : Icons.star_border,
            size: 20,
            color: featured ? AppColors.gold : AppColors.textTertiary,
          ),
          onPressed: acting ? null : () => _feature(id, !featured),
        ),
        SizedBox(
          width: 116,
          child: AppButton(
            text: suspended ? 'Réactiver' : 'Suspendre',
            type: suspended ? AppButtonType.primary : AppButtonType.secondary,
            onPressed:
                acting ? null : () => suspended ? _restore(id) : _suspend(id),
          ),
        ),
      ],
    );
  }
}

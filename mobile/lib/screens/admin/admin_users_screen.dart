import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/admin/admin_users_provider.dart';
import '../../widgets/common/app_button.dart';
import 'widgets/admin_data_table.dart';
import 'widgets/admin_scaffold.dart';
import 'widgets/admin_search_field.dart';
import 'widgets/admin_segmented_control.dart';
import 'widgets/reason_dialog.dart';
import 'widgets/status_chip.dart';

/// Consumer (user) management: filter + search + ban / réactiver.
/// Design: docs/design/admin-console-ui.md §3.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AdminUsersProvider>().load(),
    );
  }

  Future<void> _ban(String id) async {
    final reason = await showReasonDialog(
      context,
      title: 'Bannir ce client ?',
      confirmLabel: 'Bannir',
      hint: 'Motif (interne)',
      reasonRequired: false,
    );
    if (reason == null || !mounted) return;
    await _run(() => context.read<AdminUsersProvider>().ban(id, reason),
        'Client banni');
  }

  Future<void> _unban(String id) => _run(
      () => context.read<AdminUsersProvider>().unban(id), 'Client réactivé');

  Future<void> _run(Future<bool> Function() action, String okMsg) async {
    final p = context.read<AdminUsersProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await action();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? okMsg : (p.actionError ?? 'Échec'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminUsersProvider>();
    return AdminScaffold(
      title: 'Clients',
      actions: [
        AdminSearchField(
          hint: 'Nom ou téléphone…',
          onSubmitted: (q) => context.read<AdminUsersProvider>().search(q),
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminSegmentedControl(
              labels: const ['Tous', 'Actifs', 'Bannis'],
              selected: p.filter,
              onSelect: (i) => context.read<AdminUsersProvider>().setFilter(i),
            ),
            const SizedBox(height: AppTheme.spacingM),
            AdminDataTable(
              isLoading: p.isLoading,
              error: p.error,
              onRetry: () => context.read<AdminUsersProvider>().load(),
              emptyIcon: Icons.people_outline,
              emptyTitle: 'Aucun client',
              emptyDescription: 'Aucun client ne correspond à ce filtre.',
              columns: const [
                AdminColumn('Nom', flex: 3),
                AdminColumn('Téléphone', flex: 2),
                AdminColumn('Statut', flex: 2),
                AdminColumn('Action', flex: 2),
              ],
              rows: [
                for (final r in p.items)
                  AdminRow(
                    onTap: () => context.push('/admin/users/${r['id']}'),
                    cells: [
                      Text('${r['name'] ?? 'Client'}',
                          style: AppTextStyles.bodyMedium),
                      Text('${r['phoneNumber'] ?? '—'}',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textSecondary)),
                      Align(
                        alignment: Alignment.centerLeft,
                        child:
                            StatusChip.forStatus('${r['status'] ?? 'active'}'),
                      ),
                      _action(r, p.acting),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(Map<String, dynamic> r, bool acting) {
    final id = '${r['id']}';
    final banned = r['status'] == 'banned';
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 116,
        child: AppButton(
          text: banned ? 'Réactiver' : 'Bannir',
          type: banned ? AppButtonType.primary : AppButtonType.secondary,
          onPressed: acting ? null : () => banned ? _unban(id) : _ban(id),
        ),
      ),
    );
  }
}

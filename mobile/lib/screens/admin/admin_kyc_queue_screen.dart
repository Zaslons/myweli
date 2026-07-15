import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/admin/admin_kyc_provider.dart';
import 'widgets/admin_data_table.dart';
import 'widgets/admin_scaffold.dart';

/// KYC approval queue — pending providers in a data table. Row → detail.
/// Design: docs/design/admin-console-ui.md §3.
class AdminKycQueueScreen extends StatefulWidget {
  const AdminKycQueueScreen({super.key});

  @override
  State<AdminKycQueueScreen> createState() => _AdminKycQueueScreenState();
}

class _AdminKycQueueScreenState extends State<AdminKycQueueScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AdminKycProvider>().loadQueue(),
    );
  }

  String _date(Object? iso) {
    final s = iso?.toString() ?? '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminKycProvider>();
    return AdminScaffold(
      title: 'KYC — en attente',
      actions: [
        IconButton(
          tooltip: 'Rafraîchir',
          icon: const Icon(Icons.refresh, size: AppTheme.iconS),
          onPressed: () => context.read<AdminKycProvider>().loadQueue(),
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        child: AdminDataTable(
          isLoading: p.isLoading,
          error: p.error,
          onRetry: () => context.read<AdminKycProvider>().loadQueue(),
          emptyIcon: Icons.verified_user_outlined,
          emptyTitle: 'Aucune vérification en attente',
          emptyDescription: 'Les nouvelles soumissions KYC apparaîtront ici.',
          columns: const [
            AdminColumn('Salon', flex: 3),
            AdminColumn('Type', flex: 2),
            AdminColumn('Soumis le', flex: 2),
            AdminColumn('Documents', flex: 2),
          ],
          rows: [
            for (final item in p.queue)
              AdminRow(
                onTap: () => context.go('/admin/kyc/${item['accountId']}'),
                cells: [
                  Text('${item['businessName'] ?? '—'}',
                      style: AppTextStyles.bodyMedium),
                  Text('${item['businessType'] ?? ''}',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary)),
                  Text(_date(item['submittedAt']),
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary)),
                  Text('${item['docCount'] ?? 0} document(s)',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

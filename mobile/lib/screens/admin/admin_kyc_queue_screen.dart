import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/admin/admin_kyc_provider.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_indicator.dart';

/// KYC approval queue — pending providers. Tap a row → detail.
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

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminKycProvider>();
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('KYC — en attente')),
      body: Builder(
        builder: (context) {
          if (p.isLoading && p.queue.isEmpty) return const LoadingIndicator();
          if (p.error != null && p.queue.isEmpty) {
            return Center(child: Text(p.error!));
          }
          if (p.queue.isEmpty) {
            return const EmptyState(
              icon: Icons.verified_user_outlined,
              title: 'Aucune vérification en attente',
              description: 'Les nouvelles soumissions KYC apparaîtront ici.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => context.read<AdminKycProvider>().loadQueue(),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              itemCount: p.queue.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final item = p.queue[i];
                return ListTile(
                  tileColor: AppColors.secondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                  title: Text('${item['businessName'] ?? '—'}'),
                  subtitle: Text(
                    '${item['businessType'] ?? ''} · '
                    '${item['docCount'] ?? 0} document(s)',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/admin/kyc/${item['accountId']}'),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

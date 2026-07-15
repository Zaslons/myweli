import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/admin/admin_dashboard_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/loading_indicator.dart';
import 'widgets/admin_scaffold.dart';
import 'widgets/stat_card.dart';

/// Marketplace-health KPI dashboard (read-only). Design: docs/design/admin-console-ui.md §3.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AdminDashboardProvider>().load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminDashboardProvider>();
    return AdminScaffold(
      title: "Vue d'ensemble",
      actions: [
        IconButton(
          tooltip: 'Rafraîchir',
          icon: const Icon(Icons.refresh, size: AppTheme.iconS),
          onPressed: () => context.read<AdminDashboardProvider>().load(),
        ),
      ],
      child: _body(context, p),
    );
  }

  Widget _body(BuildContext context, AdminDashboardProvider p) {
    if (p.isLoading && p.overview == null) return const LoadingIndicator();
    if (p.overview == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(p.error ?? 'Erreur', style: AppTextStyles.bodyMedium),
            const SizedBox(height: AppTheme.spacingM),
            AppButton(
              text: 'Réessayer',
              type: AppButtonType.secondary,
              onPressed: () => context.read<AdminDashboardProvider>().load(),
            ),
          ],
        ),
      );
    }
    final o = p.overview!;
    Map<String, dynamic> m(String k) =>
        (o[k] as Map?)?.cast<String, dynamic>() ?? const {};
    final users = m('users');
    final providers = m('providers');
    final verif = m('verification');
    final bookings = m('bookings');
    final guard = m('guardrails');
    final disputes = m('disputes');
    String pct(Object? v) =>
        '${(((v as num?) ?? 0) * 100).toStringAsFixed(1)}%';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('À traiter', style: AppTextStyles.titleSmall),
          const SizedBox(height: AppTheme.spacingS),
          Wrap(
            spacing: AppTheme.spacingM,
            runSpacing: AppTheme.spacingM,
            children: [
              StatCard(
                label: 'KYC en attente',
                value: '${verif['pending'] ?? 0}',
                accent: true,
                onTap: () => context.go('/admin/kyc'),
              ),
              StatCard(
                label: 'Litiges ouverts',
                value: '${disputes['open'] ?? 0}',
                accent: true,
              ),
              StatCard(
                label: 'Avis signalés',
                value: '${o['reportedReviews'] ?? 0}',
                accent: true,
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingL),
          Text('Activité', style: AppTextStyles.titleSmall),
          const SizedBox(height: AppTheme.spacingS),
          Wrap(
            spacing: AppTheme.spacingM,
            runSpacing: AppTheme.spacingM,
            children: [
              StatCard(
                label: 'Rendez-vous (total)',
                value: '${bookings['total'] ?? 0}',
              ),
              StatCard(
                  label: 'Terminés', value: '${bookings['completed'] ?? 0}'),
              StatCard(
                label: 'Taux de no-show',
                value: pct(guard['noShowRate']),
              ),
              StatCard(
                label: 'Taux d’annulation',
                value: pct(guard['cancellationRate']),
              ),
              StatCard(
                label: 'Salons vérifiés',
                value: '${verif['verified'] ?? 0}',
              ),
              StatCard(
                label: 'Salons actifs',
                value: '${providers['active'] ?? 0}',
              ),
              StatCard(
                label: 'Salons suspendus',
                value: '${providers['suspended'] ?? 0}',
              ),
              StatCard(
                  label: 'Clients actifs', value: '${users['active'] ?? 0}'),
              StatCard(
                  label: 'Clients bannis', value: '${users['banned'] ?? 0}'),
            ],
          ),
        ],
      ),
    );
  }
}

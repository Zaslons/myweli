import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/admin/admin_dashboard_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/loading_indicator.dart';

/// Marketplace-health KPI dashboard (read-only). Design: docs/design/admin-console-ui.md.
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
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Tableau de bord')),
      body: Builder(
        builder: (context) {
          if (p.isLoading && p.overview == null) {
            return const LoadingIndicator();
          }
          if (p.overview == null) {
            return _ErrorRetry(
              message: p.error ?? 'Erreur',
              onRetry: () => context.read<AdminDashboardProvider>().load(),
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
            child: Wrap(
              spacing: AppTheme.spacingM,
              runSpacing: AppTheme.spacingM,
              children: [
                _Card('Rendez-vous (total)', '${bookings['total'] ?? 0}'),
                _Card('Terminés', '${bookings['completed'] ?? 0}'),
                _Card('Taux de no-show', pct(guard['noShowRate']),
                    accent: true),
                _Card('Taux d’annulation', pct(guard['cancellationRate'])),
                _Card('KYC en attente', '${verif['pending'] ?? 0}',
                    accent: true),
                _Card('Salons vérifiés', '${verif['verified'] ?? 0}'),
                _Card('Salons actifs', '${providers['active'] ?? 0}'),
                _Card('Salons suspendus', '${providers['suspended'] ?? 0}'),
                _Card('Litiges ouverts', '${disputes['open'] ?? 0}',
                    accent: true),
                _Card('Avis signalés', '${o['reportedReviews'] ?? 0}'),
                _Card('Clients actifs', '${users['active'] ?? 0}'),
                _Card('Clients bannis', '${users['banned'] ?? 0}'),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card(this.label, this.value, {this.accent = false});
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(
          color: accent ? AppColors.primary : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTextStyles.headlineMedium
                .copyWith(color: accent ? AppColors.primary : null),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: AppTextStyles.bodyMedium),
          const SizedBox(height: AppTheme.spacingM),
          AppButton(
            text: 'Réessayer',
            type: AppButtonType.secondary,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

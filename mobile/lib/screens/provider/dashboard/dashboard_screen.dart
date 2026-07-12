import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/brand_refresh.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/pro_membership.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_dashboard_provider.dart';
import '../../../widgets/push/push_permission_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _resolvedProviderId(BuildContext context) {
    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    return authProvider.activeSalonId ?? '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.provider != null) {
        final dashboardProvider =
            Provider.of<ProDashboardProvider>(context, listen: false);
        dashboardProvider.loadDashboardStats(_resolvedProviderId(context));
        _maybeAskPush();
      }
    });
  }

  /// On the first dashboard visit, offer to enable push (once). Best-effort —
  /// pros want new-booking alerts immediately, so we ask here rather than later.
  Future<void> _maybeAskPush() async {
    if (!mounted) return;
    await serviceLocator.proPushRegistration.maybePromptOnce(
      () => showPushPermissionSheet(
        context,
        body: 'Soyez prévenu·e dès qu’un client réserve, annule ou modifie '
            'un rendez-vous, et ne manquez aucune demande.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Tableau de bord'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () => context.push('/pro/profile'),
          ),
        ],
      ),
      body: Consumer2<ProAuthProvider, ProDashboardProvider>(
        builder: (context, authProvider, dashboardProvider, _) {
          if (!authProvider.isAuthenticated) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline,
                      size: 64, color: AppColors.textSecondary),
                  const SizedBox(height: 16),
                  Text(
                    'Veuillez vous connecter',
                    style: AppTextStyles.titleLarge
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go('/pro/login'),
                    child: const Text('Se connecter'),
                  ),
                ],
              ),
            );
          }

          if (dashboardProvider.isLoading) {
            return const Center(child: LoadingIndicator());
          }

          final stats = dashboardProvider.stats;
          if (stats == null) {
            return Center(
              child: Text(
                dashboardProvider.error ?? 'Aucune donnée disponible',
                style: AppTextStyles.bodyLarge
                    .copyWith(color: AppColors.textSecondary),
              ),
            );
          }

          return BrandRefresh(
            onRefresh: () async {
              if (authProvider.provider != null) {
                await dashboardProvider
                    .loadDashboardStats(_resolvedProviderId(context));
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppTheme.spacingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bienvenue, ${authProvider.salonName}',
                    style: AppTextStyles.headlineMedium
                        .copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  // Go-live is owner-only (salon.publish, sign-off) — the
                  // card hides for members; the server 403s regardless.
                  if (authProvider.can(ProCap.salonPublish)) ...[
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.checklist_rounded),
                        title: const Text('Configurer mon profil'),
                        subtitle: const Text(
                            'Complétez les étapes pour aller en ligne'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/pro/onboarding'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 16),
                  // Stats Cards
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Aujourd\'hui',
                          value: stats.todayAppointments.toString(),
                          subtitle: 'Rendez-vous',
                          icon: Icons.calendar_today,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          title: 'En attente',
                          value: stats.pendingRequests.toString(),
                          subtitle: 'Demandes',
                          icon: Icons.pending,
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                  // Money figures are field-gated server-side without
                  // finances.view (R1/R4) — absence is a valid state.
                  if (stats.hasRevenue) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            title: 'Aujourd\'hui',
                            value:
                                Formatters.formatCurrency(stats.todayRevenue!),
                            subtitle: 'Revenus',
                            icon: Icons.attach_money,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            title: 'Ce mois',
                            value:
                                Formatters.formatCurrency(stats.monthRevenue!),
                            subtitle: 'Revenus',
                            icon: Icons.trending_up,
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Role-gated sections (access R4b): UI hiding is
                  // convenience — the routes 403 server-side regardless.
                  ..._section(context, 'Opérations quotidiennes', [
                    if (authProvider.can(ProCap.journalViewAll))
                      _ActionCard(
                        title: 'Rendez-vous',
                        icon: Icons.calendar_today,
                        onTap: () => context.push('/pro/journal'),
                      ),
                    if (authProvider.can(ProCap.clientsView))
                      _ActionCard(
                        title: 'Clients',
                        icon: Icons.people,
                        onTap: () => context.push('/pro/clients'),
                      ),
                    if (authProvider.can(ProCap.availabilityManage))
                      _ActionCard(
                        title: 'Disponibilité',
                        icon: Icons.access_time,
                        onTap: () => context.push('/pro/availability'),
                      ),
                  ]),
                  ..._section(context, 'Configuration', [
                    if (authProvider.can(ProCap.catalogueManage)) ...[
                      _ActionCard(
                        title: 'Services',
                        icon: Icons.build,
                        onTap: () => context.push('/pro/services'),
                      ),
                      _ActionCard(
                        title: 'Employés',
                        icon: Icons.people,
                        onTap: () => context.push('/pro/artists'),
                      ),
                    ],
                  ]),
                  ..._section(context, 'Analyses', [
                    if (authProvider.can(ProCap.financesView))
                      _ActionCard(
                        title: 'Revenus',
                        icon: Icons.attach_money,
                        onTap: () => context.push('/pro/earnings'),
                      ),
                    if (authProvider.can(ProCap.profileManage))
                      _ActionCard(
                        title: 'Avis',
                        icon: Icons.star,
                        onTap: () => context.push('/pro/reviews'),
                      ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A titled action grid, omitted entirely when the role leaves it empty.
List<Widget> _section(BuildContext context, String title, List<Widget> cards) {
  if (cards.isEmpty) return const [];
  return [
    Text(
      title,
      style: AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimary),
    ),
    const SizedBox(height: 12),
    GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.1,
      children: cards,
    ),
    const SizedBox(height: 24),
  ];
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        boxShadow: AppTheme.elevation1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.headlineSmall
                .copyWith(color: AppColors.textPrimary),
          ),
          Text(
            subtitle,
            style:
                AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: BoxDecoration(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(AppTheme.radiusXL),
          boxShadow: AppTheme.elevation1,
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppColors.primary),
            const SizedBox(height: 8),
            Text(
              title,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

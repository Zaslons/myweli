import 'package:flutter/material.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/salon_time.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_earnings_provider.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.provider != null) {
        final earningsProvider =
            Provider.of<ProEarningsProvider>(context, listen: false);
        earningsProvider.loadEarnings(authProvider.provider!.id);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadEarningsForTab(int index) {
    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || authProvider.provider == null) return;

    final earningsProvider =
        Provider.of<ProEarningsProvider>(context, listen: false);
    // Period buckets on SALON days (salon_time.dart) — the old device-local
    // math drifted off-UTC, and the week even started at Monday's current
    // HOUR instead of its midnight.
    final today = salonToday();

    DateTime? startDate;
    DateTime? endDate;

    switch (index) {
      case 0: // Today
        startDate = today;
        endDate = today.add(const Duration(days: 1));
        break;
      case 1: // Week (Monday-start)
        startDate = today.subtract(Duration(days: today.weekday - 1));
        endDate = startDate.add(const Duration(days: 7));
        break;
      case 2: // Month
        startDate = DateTime.utc(today.year, today.month, 1);
        endDate = DateTime.utc(today.year, today.month + 1, 1);
        break;
      case 3: // All
        break;
    }

    earningsProvider.loadEarnings(
      authProvider.provider!.id,
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Revenus'),
        bottom: TabBar(
          controller: _tabController,
          onTap: _loadEarningsForTab,
          tabs: const [
            Tab(text: 'Aujourd\'hui'),
            Tab(text: 'Semaine'),
            Tab(text: 'Mois'),
            Tab(text: 'Tout'),
          ],
        ),
      ),
      body: Consumer2<ProAuthProvider, ProEarningsProvider>(
        builder: (context, authProvider, earningsProvider, _) {
          if (!authProvider.isAuthenticated) {
            return const Center(child: Text('Veuillez vous connecter'));
          }

          if (earningsProvider.isLoading) {
            return const Center(child: LoadingIndicator());
          }

          final earnings = earningsProvider.earnings;
          if (earnings == null) {
            return Center(
              child: Text(
                earningsProvider.error ?? 'Aucune donnée disponible',
                style: AppTextStyles.bodyLarge
                    .copyWith(color: AppColors.textSecondary),
              ),
            );
          }

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingL),
                color: AppColors.secondary,
                child: Column(
                  children: [
                    Text(
                      'Total',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      Formatters.formatCurrency(earnings.totalEarnings),
                      style: AppTextStyles.headlineLarge
                          .copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: earnings.transactions.isEmpty
                    ? Center(
                        child: Text(
                          'Aucune transaction',
                          style: AppTextStyles.bodyLarge
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppTheme.spacingM),
                        itemCount: earnings.transactions.length,
                        itemBuilder: (context, index) {
                          final transaction = earnings.transactions[index];
                          return Card(
                            margin: const EdgeInsets.only(
                                bottom: AppTheme.spacingM),
                            child: ListTile(
                              title: Text(
                                  Formatters.formatDateTime(transaction.date)),
                              trailing: Text(
                                Formatters.formatCurrency(transaction.amount),
                                style: AppTextStyles.titleMedium
                                    .copyWith(color: AppColors.primary),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

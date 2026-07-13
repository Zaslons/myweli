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
    // Period buckets on the ACTIVE SALON's days (salon_time.dart, MP2):
    // bounds are UTC instants of the salon's midnights.
    final tz = authProvider.salonTimezone;
    final today = salonToday(tz: tz);

    DateTime? startDate;
    DateTime? endDate;

    switch (index) {
      case 0: // Today
        final bounds = salonDayBoundsUtc(tz: tz);
        startDate = bounds.startUtc;
        endDate = bounds.endUtc;
        break;
      case 1: // Week (Monday-start)
        final monday = today.subtract(Duration(days: today.weekday - 1));
        startDate =
            salonWallClockToUtc(monday.year, monday.month, monday.day, tz: tz);
        endDate = salonWallClockToUtc(monday.year, monday.month, monday.day + 7,
            tz: tz);
        break;
      case 2: // Month
        startDate = salonWallClockToUtc(today.year, today.month, 1, tz: tz);
        endDate = salonWallClockToUtc(today.year, today.month + 1, 1, tz: tz);
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
                      Formatters.formatCurrency(
                        earnings.totalEarnings,
                        currency:
                            earnings.currency ?? authProvider.salonCurrency,
                      ),
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
                              title: Text(Formatters.formatDateTime(toSalonTime(
                                  transaction.date,
                                  tz: authProvider.salonTimezone))),
                              trailing: Text(
                                Formatters.formatCurrency(
                                  transaction.amount,
                                  currency: earnings.currency ??
                                      authProvider.salonCurrency,
                                ),
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

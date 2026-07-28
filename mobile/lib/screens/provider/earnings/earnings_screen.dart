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
        // R6: the ACTIVE salon, not the account. `ProAuthProvider.activeSalonId`
        // documents the rule at its declaration — "screens use THIS (never
        // `provider.id` — an account id is not a salon id)" — and every other pro
        // screen follows it. This one did not, so `getEarnings` filtered
        // appointments on an account id and matched nothing: the screen showed
        // « 0 FCFA » and « Aucune transaction » for a salon that had takings, and
        // a multi-salon owner's switch never reached it.
        earningsProvider.loadEarnings(authProvider.activeSalonId ?? '');
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
      authProvider.activeSalonId ?? '',
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
          // §13.3's width twin. A non-scrollable `TabBar` wraps every tab in
          // `Expanded` (tabs.dart:1977), so each gets exactly `W/n` — and a
          // `Tab`'s label is `softWrap: false, overflow: fade` (tabs.dart:183),
          // so a label too long for its share is **faded away without throwing**.
          // No overflow, no exception: A10 photographed this bar with
          // « Aujourd’hui » cut off and 777 tests had nothing to say.
          //
          // `center`, explicitly, and NOT the M3 default: that is
          // `TabAlignment.startOffset` (tabs.dart:2727), which spends 52dp on an
          // empty leading gutter — 14% of a 360dp screen — and is not accounted
          // for in the scroll-centring math (tabs.dart:1669-1683 reads
          // `widget.padding` only), so the selected tab lands 52dp off-centre.
          //
          // `center` is also the ONLY alignment legal in both modes
          // (tabs.dart:1809-1821), and it degrades correctly: the strip
          // shrink-wraps and is genuinely centred while the labels fit, and once
          // they do not the viewport clamps to full width, centring becomes a
          // no-op and the bar start-anchors and scrolls.
          //
          // It must stay HERE and never move to `tabBarTheme`: the assert is
          // evaluated per-bar against that bar's own `isScrollable`, so a
          // theme-level value would throw on every non-scrollable bar.
          isScrollable: true,
          tabAlignment: TabAlignment.center,
          tabs: const [
            Tab(text: 'Aujourd’hui'),
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
                    const SizedBox(height: AppTheme.spacingS),
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

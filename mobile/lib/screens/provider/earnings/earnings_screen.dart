import 'package:flutter/material.dart';
import 'package:myweli/widgets/common/empty_state.dart';
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
      // **The first load is the SELECTED TAB's load** (§21 row 40, fourth
      // defect). This used to hand-roll `loadEarnings(activeSalonId)` with no
      // date bounds at all, while every tab tap passes them — so the screen
      // opened on « Aujourd'hui » showing *every transaction the salon has ever
      // taken*, and only started telling the truth once the user touched a tab.
      // A10's golden photographed exactly that: « dimanche 1 mars 2026 » under
      // a tab labelled today, with the clock frozen to 11 March.
      //
      // Delegating to `_loadEarningsForTab` rather than repeating its body is
      // the fix and the guard against the next one: there is now one definition
      // of what each bucket means, and `initState` cannot drift from `onTap`.
      // (The R6 rule the old body documented — the ACTIVE salon id, never the
      // account id — lives on at `:87`, where the delegate reads it.)
      _loadEarningsForTab(_tabController.index);
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
              // §12/§6 (§21 row 40, second defect): this was a bare
              // `Container(color: secondary)` — no radius, no elevation, no
              // margin — so the app's headline number read as an unstyled band
              // welded to the tab bar. It is a surface; it gets surface tokens.
              Container(
                margin: const EdgeInsets.all(AppTheme.spacingM),
                padding: const EdgeInsets.all(AppTheme.spacingL),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                  boxShadow: AppTheme.elevation1,
                ),
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
                    // §12 (§21 row 40, third defect): a bare `Center(Text(…))`
                    // met the four-states contract in name only — no icon, no
                    // title, no explanation. It matters more now than it did:
                    // fixing the first-load bug above makes « Aujourd'hui » the
                    // FIRST thing most salons see, because most salons have no
                    // takings yet at the moment they open the screen.
                    ? const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'Aucune transaction',
                        description:
                            'Les paiements encaissés sur cette période '
                            'apparaîtront ici.',
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

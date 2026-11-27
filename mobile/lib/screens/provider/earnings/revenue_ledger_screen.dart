import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/revenue_periods.dart';
import '../../../core/utils/revenue_wording.dart';
import '../../../core/utils/salon_id.dart';
import '../../../core/utils/salon_time.dart';
import '../../../models/revenue_analytics.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_revenue_provider.dart';
import '../../../widgets/common/app_async_view.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_chip.dart';
import '../../../widgets/common/app_skeleton.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/screen_title.dart';
import '../../../widgets/pro/revenue/revenue_ledger_tile.dart';

/// « Rendez-vous » — the bookings behind a figure
/// (docs/design/pro-revenue-analytics.md §4.9): « Terminés » (default) ·
/// « À venir » · « À clôturer » · « Absents » · « Annulés », pages of 20 and
/// « Afficher plus » at the end (no infinite scroll: it is announced and it
/// is a control). « À venir » soonest first; the others newest first — the
/// server's order. Each row opens the booking and its « Terminé » /
/// « Absent » actions; coming back reloads the page.
///
/// Route: `/pro/earnings/rendez-vous?period=…&statut=…&asOf=…` (+ the
/// filter of the detail it was opened from, and its label).
class RevenueLedgerScreen extends StatefulWidget {
  const RevenueLedgerScreen({super.key, this.routeQuery = const {}});

  final Map<String, String> routeQuery;

  @override
  State<RevenueLedgerScreen> createState() => _RevenueLedgerScreenState();
}

class _RevenueLedgerScreenState extends State<RevenueLedgerScreen> {
  static const _key = 'registre';

  late final RevenueQuery _query = RevenueQuery.fromRouteQuery(
    widget.routeQuery,
    artistId: _id(widget.routeQuery['artistId']),
    serviceId: _id(widget.routeQuery['serviceId']),
    channel: RevenueChannel.values
        .where((c) => c.name == widget.routeQuery['channel'])
        .firstOrNull,
  );

  late RevenueLedgerStatus _status =
      RevenueLedgerStatus.values
          .where((s) => s.name == widget.routeQuery['statut'])
          .firstOrNull ??
      RevenueLedgerStatus.completed;

  /// The figures' `asOf` — so « À clôturer » lists what the banner counted.
  /// The server takes one from the last 24 hours only: an older link (a
  /// screen kept open overnight) asks the server's now instead.
  late final DateTime? _asOf = () {
    final at = DateTime.tryParse(widget.routeQuery['asOf'] ?? '')?.toUtc();
    if (at == null) return null;
    final age = AppClock.now().toUtc().difference(at);
    return (age.isNegative || age > const Duration(hours: 23)) ? null : at;
  }();

  static String? _id(String? v) =>
      (v != null && RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(v)) ? v : null;

  SalonId get _salon =>
      context.read<ProAuthProvider>().activeSalonId ?? SalonId.none;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() => context.read<ProRevenueProvider>().loadLedger(
    _salon,
    _key,
    _query,
    _status,
    asOf: _asOf,
  );

  void _choose(RevenueLedgerStatus s) {
    if (s == _status) return;
    setState(() => _status = s);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ProAuthProvider>();
    final provider = context.watch<ProRevenueProvider>();
    final ledger = provider.ledger(_key);
    final tz = auth.salonTimezone;
    final period = provisionalRevenueTitle(
      _query,
      today: salonToday(now: _asOf, tz: tz),
    );
    final label = widget.routeQuery['libelle'];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const ScreenTitle('Rendez-vous')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingM,
              AppTheme.spacingM,
              AppTheme.spacingM,
              AppTheme.spacingS,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (period != null || label != null)
                  Text(
                    [?label, ?period].join(' · '),
                    style: AppTextStyles.titleSmall.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                const SizedBox(height: AppTheme.spacingS),
                // Every filter in sight: they wrap, as « Revenus »'s periods.
                Wrap(
                  spacing: AppTheme.spacingS,
                  runSpacing: AppTheme.spacingS,
                  children: [
                    for (final s in RevenueLedgerStatus.values)
                      AppChip.choice(
                        label: revenueLedgerStatusLabel(s),
                        selected: s == _status,
                        onSelected: (_) => _choose(s),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: _body(provider, ledger)),
        ],
      ),
    );
  }

  Widget _body(ProRevenueProvider provider, RevenueLedgerView? ledger) {
    if (ledger == null || ledger.isLoading || ledger.status != _status) {
      return const SkeletonTileList(label: 'Chargement des rendez-vous…');
    }
    if (ledger.refused) {
      return const EmptyState(
        icon: Icons.lock_outline,
        title: 'Réservé au propriétaire',
        description: 'Seul le propriétaire du salon voit les revenus.',
      );
    }
    if (ledger.loadError case final e?) {
      return AppErrorView(message: e, onRetry: _load);
    }
    if (ledger.items.isEmpty) {
      return EmptyState(
        icon: Icons.event_note_outlined,
        title: 'Aucun rendez-vous',
        description: revenueLedgerEmpty(_status),
      );
    }
    final salon = _salon;
    final tz = context.read<ProAuthProvider>().salonTimezone ?? kSalonTz;
    return ListView.builder(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      itemCount: ledger.items.length + 1,
      itemBuilder: (context, i) {
        if (i < ledger.items.length) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
            child: RevenueLedgerTile(
              row: ledger.items[i],
              salonId: salon,
              timezone: tz,
              onReturn: _load,
            ),
          );
        }
        return _Footer(
          ledger: ledger,
          onMore: () => provider.loadMoreLedger(salon, _key),
        );
      },
    );
  }
}

/// How many are shown, and « Afficher plus » while there are more.
class _Footer extends StatelessWidget {
  const _Footer({required this.ledger, required this.onMore});

  final RevenueLedgerView ledger;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppTheme.spacingS),
    child: Column(
      children: [
        // Announced when « Afficher plus » adds a page.
        Semantics(
          liveRegion: true,
          child: Text(
            '${ledger.items.length} sur '
            '${Formatters.count(ledger.total, 'rendez-vous', 'rendez-vous')}',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ),
        if (ledger.moreError case final e?) ...[
          const SizedBox(height: AppTheme.spacingS),
          Text(
            e,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
        if (ledger.hasMore) ...[
          const SizedBox(height: AppTheme.spacingS),
          AppButton(
            text: 'Afficher plus',
            type: AppButtonType.secondary,
            isLoading: ledger.isLoadingMore,
            onPressed: onMore,
          ),
        ],
        const SizedBox(height: AppTheme.spacingL),
      ],
    ),
  );
}

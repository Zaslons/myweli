import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
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
import '../../../widgets/common/app_card.dart';
import '../../../widgets/common/app_chip.dart';
import '../../../widgets/common/app_skeleton.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/label_value_row.dart';
import '../../../widgets/common/screen_title.dart';
import '../../../widgets/common/section_heading.dart';
import '../../../widgets/common/status_banner.dart';
import '../../../widgets/pro/revenue/bar_series.dart';
import '../../../widgets/pro/revenue/delta_badge.dart';
import '../../../widgets/pro/revenue/kpi_grid.dart';
import '../../../widgets/pro/revenue/revenue_ledger_tile.dart';
import '../../../widgets/pro/revenue/share_bar.dart';
import 'revenue_sheets.dart';

/// « Revenus » — the salon's revenue analytics in the Pro app
/// (docs/design/pro-revenue-analytics.md §4): one period and its
/// comparison, five figures, « Évolution », the revenue by collaborateur,
/// prestation and canal (each row opening its detail), and the latest
/// completed bookings. Owner only (`finances.view`, checked by the server).
///
/// **The server owns every figure** (§3): this screen draws the answer and
/// steps the calendar from it, and computes nothing.
class RevenueScreen extends StatelessWidget {
  const RevenueScreen({super.key, this.routeQuery = const {}});

  /// The period in the route (`?period=month&date=…&compare=…`, §4.1).
  final Map<String, String> routeQuery;

  @override
  Widget build(BuildContext context) => RevenueAnalyticsPage(
    viewKey: 'revenus',
    routeQuery: routeQuery,
    fallbackTitle: 'Revenus',
  );
}

/// The path of a row's detail (§4.1): `/pro/earnings/collaborateur/:id`,
/// `…/prestation/:id`, `…/canal/:channel`, with the period in the query.
String revenueDetailLocation(
  RevenueAxis axis,
  String? key,
  RevenueQuery query, {
  String? label,
}) {
  // Three literal paths, so the route gate (route_literals_test) reads each
  // one against the router.
  final id = key ?? RevenueQuery.kNoArtist;
  final path = switch (axis) {
    RevenueAxis.artist => '/pro/earnings/collaborateur/$id',
    RevenueAxis.service => '/pro/earnings/prestation/$id',
    RevenueAxis.channel => '/pro/earnings/canal/$id',
  };
  return Uri(
    path: path,
    queryParameters: {...query.toRouteQuery(), 'libelle': ?label},
  ).toString();
}

/// The ledger's location (§4.9): the period, the filter, the status and the
/// figures' `asOf`.
String revenueLedgerLocation(
  RevenueQuery query,
  RevenueLedgerStatus status, {
  DateTime? asOf,
  String? label,
}) => Uri(
  path: '/pro/earnings/rendez-vous',
  queryParameters: {
    ...query.toRouteQuery(),
    'artistId': ?query.artistId,
    'serviceId': ?query.serviceId,
    'channel': ?query.channel?.name,
    'statut': status.name,
    if (asOf != null) 'asOf': asOf.toUtc().toIso8601String(),
    'libelle': ?label,
  },
).toString();

/// The page behind « Revenus » and each of its details (§4.2, §4.8): the
/// period bar, then the content in its state (§4.11).
class RevenueAnalyticsPage extends StatefulWidget {
  const RevenueAnalyticsPage({
    super.key,
    required this.viewKey,
    required this.routeQuery,
    required this.fallbackTitle,
    this.filterAxis,
    this.filterKey,
  });

  /// The provider's key for this screen's figures.
  final String viewKey;
  final Map<String, String> routeQuery;

  /// The bar's title: « Revenus », or the kind of row a detail is about.
  final String fallbackTitle;

  /// A detail's axis and row key; null on « Revenus » itself.
  final RevenueAxis? filterAxis;
  final String? filterKey;

  @override
  State<RevenueAnalyticsPage> createState() => _RevenueAnalyticsPageState();
}

class _RevenueAnalyticsPageState extends State<RevenueAnalyticsPage> {
  late final List<RevenueAxis> _axes = [
    for (final a in RevenueAxis.values)
      if (a != widget.filterAxis) a,
  ];
  late RevenueAxis _tab = _axes.first;
  RevenueSort _sort = RevenueSort.amount;
  bool _listForm = false;

  /// The salon the figures on screen were asked for — a switch reloads.
  SalonId? _loadedSalon;

  /// The salon's today from the last answer: the provisional title of a
  /// query with no date (§4.11 « Period change »).
  DateTime? _lastToday;

  String get _previewKey => '${widget.viewKey}:apercu';

  bool get _isDetail => widget.filterAxis != null;

  RevenueQuery _initialQuery(RevenueCompare sessionCompare) {
    final axis = widget.filterAxis;
    final key = widget.filterKey;
    var q = RevenueQuery.fromRouteQuery(
      widget.routeQuery,
      artistId: axis == RevenueAxis.artist ? key : null,
      serviceId: axis == RevenueAxis.service ? key : null,
      channel: axis == RevenueAxis.channel
          ? RevenueChannel.values.where((c) => c.name == key).firstOrNull
          : null,
    );
    // No comparison in the link: the owner's choice for the session (§4.3).
    if (!widget.routeQuery.containsKey('compare')) {
      q = q.withCompare(sessionCompare);
    }
    return q;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load(_initialQuery(context.read<ProRevenueProvider>().compare));
    });
  }

  SalonId get _salon =>
      context.read<ProAuthProvider>().activeSalonId ?? SalonId.none;

  Future<void> _load(RevenueQuery q) async {
    final provider = context.read<ProRevenueProvider>();
    final salon = _salon;
    _loadedSalon = salon;
    await provider.load(salon, widget.viewKey, q);
    if (!mounted) return;
    final view = provider.view(widget.viewKey);
    final a = view?.analytics;
    if (view == null || view.query != q || a == null) return;
    _lastToday = revenueToday(a);
    final completed = a.groups.fold<int>(
      0,
      (n, g) => n + g.current.completedCount,
    );
    if (completed > 0) {
      await provider.loadLedger(
        salon,
        _previewKey,
        q,
        RevenueLedgerStatus.completed,
        asOf: a.asOf,
        pageSize: 5,
      );
    }
  }

  void _reload(RevenueQuery q) => _load(q);

  Future<void> _openLedger(
    RevenueQuery q,
    RevenueLedgerStatus status,
    DateTime? asOf,
  ) async {
    final a = context
        .read<ProRevenueProvider>()
        .view(widget.viewKey)
        ?.analytics;
    final axis = widget.filterAxis;
    await context.push(
      revenueLedgerLocation(
        q,
        status,
        asOf: asOf,
        // A detail's ledger says whose bookings these are.
        label: axis == null || a == null
            ? null
            : revenueFilterLabel(axis, a.filters),
      ),
    );
    // A booking may have been closed there (« Terminé », « Absent »).
    if (mounted) _reload(q);
  }

  Future<void> _chooseCompare(RevenueQuery q) async {
    final provider = context.read<ProRevenueProvider>();
    final chosen = await showRevenueCompareSheet(context, q.compare);
    if (chosen == null || !mounted) return;
    provider.setCompare(chosen);
    if (chosen != q.compare) _reload(q.withCompare(chosen));
  }

  Future<void> _chooseRange(RevenueQuery q, RevenueAnalytics? a) async {
    final tz = context.read<ProAuthProvider>().salonTimezone;
    final today = a == null ? salonToday(tz: tz) : revenueToday(a);
    final range = await showRevenueRangeSheet(
      context,
      latest: addRevenueDays(today, kRevenueMaxDays),
      from: q.period == RevenuePeriod.custom ? q.from : a?.from,
      to: q.period == RevenuePeriod.custom ? q.to : a?.to,
    );
    if (range == null || !mounted) return;
    _reload(
      q.withPeriod(
        period: RevenuePeriod.custom,
        from: range.from,
        to: range.to,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ProAuthProvider>();
    final provider = context.watch<ProRevenueProvider>();
    final salon = auth.activeSalonId ?? SalonId.none;
    final view = provider.view(widget.viewKey);
    final query = view?.query ?? _initialQuery(provider.compare);

    // A salon switch emptied the state: ask the new salon, same period.
    if (_loadedSalon != null && salon != _loadedSalon) {
      _loadedSalon = salon;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(query);
      });
    }

    final a = view?.analytics;
    final axis = widget.filterAxis;
    // A detail's bar says what kind of row it is: a bar title is a label,
    // never a name that can run long (SYSTEM §13.3, A15). The row's own name
    // is the page's heading, which wraps (§4.8).
    final heading = axis == null
        ? null
        : (a != null
              ? revenueFilterLabel(axis, a.filters)
              : widget.routeQuery['libelle']);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: ScreenTitle(widget.fallbackTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        children: [
          if (heading != null) ...[
            Semantics(
              header: true,
              headingLevel: 2,
              child: Text(
                heading,
                style: AppTextStyles.headlineSmall.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingM),
          ],
          // A refusal has no period to choose: nothing on the bar could
          // succeed (§4.11 « Access refused »).
          if (view?.refused != true) ...[
            _PeriodBar(
              query: query,
              analytics: a,
              // Before the first answer, the salon's today by the phone's
              // clock — for the title only, which the answer replaces; the
              // query itself still asks the server's today (§3.5).
              lastToday: _lastToday ?? salonToday(tz: auth.salonTimezone),
              onPeriod: (p) => _reload(switchRevenuePeriod(a, query, p)),
              onCustom: () => _chooseRange(query, a),
              onStep: _reload,
              onCompare: () => _chooseCompare(query),
            ),
            const SizedBox(height: AppTheme.spacingM),
          ],
          ..._content(context, auth, provider, view, query),
        ],
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    ProAuthProvider auth,
    ProRevenueProvider provider,
    RevenueView? view,
    RevenueQuery query,
  ) {
    if (view == null || view.isLoading) return const [_RevenueSkeleton()];
    if (view.refused) {
      return const [
        EmptyState(
          icon: Icons.lock_outline,
          title: 'Réservé au propriétaire',
          description: 'Seul le propriétaire du salon voit les revenus.',
        ),
      ];
    }
    final error = view.loadError;
    if (error != null) {
      return [AppErrorView(message: error, onRetry: () => _reload(query))];
    }
    final a = view.analytics;
    if (a == null) return const [_RevenueSkeleton()];
    return _success(context, auth, provider, view, a, query);
  }

  List<Widget> _success(
    BuildContext context,
    ProAuthProvider auth,
    ProRevenueProvider provider,
    RevenueView view,
    RevenueAnalytics a,
    RevenueQuery query,
  ) {
    // Nothing in either range: the figures read 0 in the salon's currency.
    final group =
        view.group ??
        RevenueGroup(
          currency: auth.salonCurrency ?? 'XOF',
          current: const RevenueFigures(),
        );
    final comparison = revenueComparisonLabel(a);
    final toClose = a.groups.fold<int>(0, (n, g) => n + g.current.toCloseCount);
    final cur = group.current;
    final rows = group.rowsOf(_tab);
    // « estimé » is only explained where it is printed: the figures, or a
    // row of the tab on screen (§4.10).
    final anyEstimated = cur.estimated || rows.any((r) => r.estimated);

    return [
      if (a.groups.length > 1) ...[
        _CurrencySwitch(
          groups: a.groups,
          selected: group.currency,
          onSelected: (c) => provider.chooseCurrency(widget.viewKey, c),
        ),
        const SizedBox(height: AppTheme.spacingM),
      ],
      if (toClose > 0) ...[
        StatusBanner(
          color: AppColors.info,
          icon: Icons.info_outline,
          title: revenueToCloseTitle(toClose),
          lines: const [
            'Confirmés mais pas encore marqués « Terminé » : ils ne '
                'comptent pas dans le réalisé.',
          ],
        ),
        // The banner has no action slot (SYSTEM §11.1): « Voir » is under it.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            text: 'Voir',
            type: AppButtonType.text,
            isFullWidth: false,
            onPressed: () =>
                _openLedger(query, RevenueLedgerStatus.toClose, a.asOf),
          ),
        ),
        const SizedBox(height: AppTheme.spacingS),
      ],
      if (!a.everCompleted && !_isDetail) ...[
        if (revenueHasFuture(a) &&
            (cur.upcomingCount > 0 || cur.pendingCount > 0)) ...[
          KpiGrid(tiles: [_upcomingTile(group)]),
          const SizedBox(height: AppTheme.spacingL),
        ],
        EmptyState(
          icon: Icons.insights_outlined,
          title: 'Pas encore de revenus',
          description:
              'Vos revenus s’afficheront ici dès votre premier rendez-vous '
              'marqué « Terminé ».',
          actionText: 'Voir les rendez-vous',
          onAction: () => context.push('/pro/journal'),
        ),
      ] else ...[
        KpiGrid(tiles: _tiles(a, group, comparison)),
        if (group.series.length >= 2 && cur.completedCount > 0) ...[
          const SizedBox(height: AppTheme.spacingL),
          ..._evolution(a, group),
        ],
        const SizedBox(height: AppTheme.spacingL),
        ..._breakdown(a, group, rows, query, comparison),
        if (cur.completedCount > 0) ...[
          const SizedBox(height: AppTheme.spacingL),
          ..._preview(provider, a, query, cur.completedCount),
        ],
      ],
      const SizedBox(height: AppTheme.spacingL),
      ..._footnotes(
        services: _tab == RevenueAxis.service && rows.isNotEmpty,
        estimated: anyEstimated,
      ),
    ];
  }

  String _money(RevenueGroup g, double v) =>
      Formatters.formatCurrency(v, currency: g.currency);

  String _sentence(String title, String value, RevenueDelta? delta) =>
      delta == null ? '$title : $value' : '$title : $value, ${delta.spoken}';

  KpiTile _upcomingTile(RevenueGroup g) {
    final cur = g.current;
    final value = _money(g, cur.upcomingAmount);
    final caption = [
      revenueUpcomingLine(cur.upcomingCount),
      if (cur.pendingCount > 0) revenuePendingLine(cur.pendingCount),
    ].join('\n');
    return KpiTile(
      title: 'Prévu',
      value: value,
      caption: caption,
      fullWidth: true,
      semanticsLabel: 'Prévu : $value, ${caption.replaceAll('\n', ', ')}',
    );
  }

  List<KpiTile> _tiles(RevenueAnalytics a, RevenueGroup g, String? cmp) {
    final cur = g.current;
    final prev = g.previous;

    final done = _money(g, cur.completedAmount);
    final doneDelta = revenueDelta(
      cur.completedAmount,
      prev?.completedAmount,
      comparison: cmp,
    );
    final countDelta = revenueDelta(
      cur.completedCount,
      prev?.completedCount,
      comparison: cmp,
    );
    final avg = cur.averageTicket;
    final avgText = avg == null ? '—' : _money(g, avg);
    final avgDelta = avg == null
        ? null
        : revenueDelta(
            avg,
            prev == null ? null : (prev.averageTicket ?? 0),
            comparison: cmp,
          );
    final rate = cur.noShowRate;
    final rateText = rate == null
        ? '—'
        : Formatters.formatPercent(rate, decimals: 1);
    final rateDelta = revenueRateDelta(rate, prev?.noShowRate, comparison: cmp);
    final absences = cur.noShowCount > 0
        ? '${revenueAbsences(cur.noShowCount)} · '
              '${_money(g, cur.noShowAmount)}'
        : null;

    return [
      KpiTile(
        title: 'Réalisé',
        value: done,
        delta: doneDelta,
        caption: cur.estimated ? 'estimé' : null,
        semanticsLabel: _sentence(
          'Réalisé',
          cur.estimated ? '$done, estimé' : done,
          doneDelta,
        ),
      ),
      KpiTile(
        title: 'Rendez-vous terminés',
        value: '${cur.completedCount}',
        delta: countDelta,
        semanticsLabel: _sentence(
          'Rendez-vous terminés',
          '${cur.completedCount}',
          countDelta,
        ),
      ),
      KpiTile(
        title: 'Panier moyen',
        value: avgText,
        delta: avgDelta,
        semanticsLabel: avg == null
            ? 'Panier moyen : aucun rendez-vous terminé'
            : _sentence('Panier moyen', avgText, avgDelta),
      ),
      KpiTile(
        title: 'Taux d’absence',
        value: rateText,
        delta: rateDelta,
        caption: absences,
        semanticsLabel: rate == null
            ? 'Taux d’absence : aucun rendez-vous terminé ni manqué'
            : '${_sentence('Taux d’absence', rateText, rateDelta)}'
                  '${absences == null ? '' : ', $absences'}',
      ),
      if (revenueHasFuture(a)) _upcomingTile(g),
    ];
  }

  List<Widget> _evolution(RevenueAnalytics a, RevenueGroup g) {
    String dateOf(RevenueSeriesPoint p) => switch (a.bucket) {
      RevenueBucket.day => Formatters.formatWeekdayDayMonthShort(p.start),
      RevenueBucket.week => Formatters.formatDayRange(p.start, p.end),
      RevenueBucket.month => Formatters.formatMonthYear(p.start),
    };
    String axisOf(RevenueSeriesPoint p) => switch (a.bucket) {
      RevenueBucket.month => Formatters.formatMonthShort(p.start),
      _ => Formatters.formatDayMonthShort(p.start),
    };
    String count(int n) => Formatters.count(n, 'rendez-vous', 'rendez-vous');
    final points = [
      for (final p in g.series)
        BarSeriesPoint(
          value: p.completedAmount,
          axisLabel: axisOf(p),
          sentence:
              '${dateOf(p)} · ${_money(g, p.completedAmount)} · '
              '${count(p.completedCount)}',
          listLabel: dateOf(p),
          listValue:
              '${_money(g, p.completedAmount)} · ${p.completedCount} rdv',
        ),
    ];
    final cur = g.current;
    return [
      SectionHeading(
        title: 'Évolution',
        headingLevel: 2,
        action: AppButton(
          text: _listForm ? 'Voir le graphique' : 'Voir en liste',
          type: AppButtonType.text,
          isFullWidth: false,
          onPressed: () => setState(() => _listForm = !_listForm),
        ),
      ),
      const SizedBox(height: AppTheme.spacingS),
      AppCard(
        child: _listForm
            ? BarSeriesList(points: points)
            : BarSeries(
                points: points,
                summary:
                    'Réalisé sur la période : '
                    '${_money(g, cur.completedAmount)} · '
                    '${count(cur.completedCount)}',
              ),
      ),
    ];
  }

  List<RevenueRow> _sorted(List<RevenueRow> rows) {
    // Rows at 0 this period (present in the comparison) stay at the bottom,
    // so a collaborateur who dropped to zero is seen (§4.7).
    final live = [
      for (final r in rows)
        if (r.current.completedAmount > 0) r,
    ];
    final zero = [
      for (final r in rows)
        if (r.current.completedAmount <= 0) r,
    ];
    final order = {for (final (i, r) in rows.indexed) r: i};
    int byServer(RevenueRow x, RevenueRow y) => order[x]!.compareTo(order[y]!);
    switch (_sort) {
      case RevenueSort.amount:
        break; // the server's order: amount, then label, then key
      case RevenueSort.count:
        live.sort((x, y) {
          final c = y.current.completedCount.compareTo(
            x.current.completedCount,
          );
          return c != 0 ? c : byServer(x, y);
        });
      case RevenueSort.name:
        int byName(RevenueRow x, RevenueRow y) {
          final c = revenueLabelOf(
            _tab,
            x,
          ).toLowerCase().compareTo(revenueLabelOf(_tab, y).toLowerCase());
          return c != 0 ? c : byServer(x, y);
        }
        live.sort(byName);
        zero.sort(byName);
    }
    return [...live, ...zero];
  }

  List<Widget> _breakdown(
    RevenueAnalytics a,
    RevenueGroup g,
    List<RevenueRow> rows,
    RevenueQuery query,
    String? cmp,
  ) {
    final cur = g.current;
    final empty = cur.completedCount == 0;
    return [
      const SectionHeading(title: 'Répartition', headingLevel: 2),
      const SizedBox(height: AppTheme.spacingS),
      Wrap(
        spacing: AppTheme.spacingS,
        runSpacing: AppTheme.spacingS,
        children: [
          for (final x in _axes)
            AppChip.choice(
              label: revenueAxisTitle(x),
              selected: _tab == x,
              onSelected: (_) => setState(() => _tab = x),
            ),
        ],
      ),
      const SizedBox(height: AppTheme.spacingS),
      if (empty)
        revenueIsFuture(a)
            ? const EmptyState(
                icon: Icons.event_outlined,
                title: 'Rien de terminé pour l’instant',
                description: 'Cette période n’a pas commencé.',
              )
            : EmptyState(
                icon: Icons.insights_outlined,
                title: 'Aucun rendez-vous terminé sur cette période',
                actionText: previousRevenuePeriod(a, query) == null
                    ? null
                    : 'Période précédente',
                onAction: previousRevenuePeriod(a, query) == null
                    ? null
                    : () => _reload(previousRevenuePeriod(a, query)!),
              )
      else ...[
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: () async {
              final s = await showRevenueSortSheet(context, _sort);
              if (s != null && mounted) setState(() => _sort = s);
            },
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Trier : ${revenueSortName(_sort)}'),
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.arrow_drop_down, size: AppTheme.iconS),
                  ),
                ],
              ),
            ),
          ),
        ),
        for (final r in _sorted(rows)) ...[
          _RowCard(
            axis: _tab,
            row: r,
            currency: g.currency,
            comparison: cmp,
            onTap: _isDetail
                ? null
                : () => context.push(
                    revenueDetailLocation(
                      _tab,
                      r.key,
                      query,
                      label: revenueLabelOf(_tab, r),
                    ),
                  ),
          ),
          const SizedBox(height: AppTheme.spacingS),
        ],
      ],
    ];
  }

  List<Widget> _preview(
    ProRevenueProvider provider,
    RevenueAnalytics a,
    RevenueQuery query,
    int completed,
  ) {
    final ledger = provider.ledger(_previewKey);
    final salon = _salon;
    return [
      SectionHeading(
        title: 'Rendez-vous terminés',
        headingLevel: 2,
        action: AppButton(
          text: 'Voir tout ($completed)',
          type: AppButtonType.text,
          isFullWidth: false,
          onPressed: () =>
              _openLedger(query, RevenueLedgerStatus.completed, a.asOf),
        ),
      ),
      const SizedBox(height: AppTheme.spacingS),
      if (ledger == null || ledger.isLoading)
        const SkeletonTileList(count: 3, label: 'Chargement des rendez-vous…')
      else if (ledger.refused || ledger.loadError != null)
        AppErrorView(
          message: ledger.loadError ?? 'Action non autorisée pour ce salon.',
          onRetry: ledger.refused
              ? null
              : () => provider.loadLedger(
                  salon,
                  _previewKey,
                  query,
                  RevenueLedgerStatus.completed,
                  asOf: a.asOf,
                  pageSize: 5,
                ),
        )
      else
        for (final row in ledger.items) ...[
          RevenueLedgerTile(
            row: row,
            salonId: salon,
            timezone: a.timezone,
            onReturn: () => _reload(query),
          ),
          const SizedBox(height: AppTheme.spacingS),
        ],
    ];
  }

  List<Widget> _footnotes({required bool services, required bool estimated}) {
    Widget note(String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
      child: Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
      ),
    );
    return [
      note(kRevenuePriceFootnote),
      if (services) note(kRevenueServicesFootnote),
      if (estimated) note(kRevenueEstimatedFootnote),
    ];
  }
}

/// The period bar (§4.3): the five chips, ‹ the period ›, « Comparé à ».
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.query,
    required this.analytics,
    required this.lastToday,
    required this.onPeriod,
    required this.onCustom,
    required this.onStep,
    required this.onCompare,
  });

  final RevenueQuery query;

  /// The answer to [query], or null while it loads.
  final RevenueAnalytics? analytics;
  final DateTime? lastToday;
  final ValueChanged<RevenuePeriod> onPeriod;
  final VoidCallback onCustom;
  final ValueChanged<RevenueQuery> onStep;
  final VoidCallback onCompare;

  static const _names = {
    RevenuePeriod.day: 'Jour',
    RevenuePeriod.week: 'Semaine',
    RevenuePeriod.month: 'Mois',
    RevenuePeriod.year: 'Année',
  };

  @override
  Widget build(BuildContext context) {
    final a = analytics;
    final title = a != null
        ? revenuePeriodTitle(a)
        : provisionalRevenueTitle(query, today: lastToday);
    final previous = a == null ? null : previousRevenuePeriod(a, query);
    final next = a == null ? null : nextRevenuePeriod(a, query);
    final compare = query.compare == RevenueCompare.none
        ? 'Aucune comparaison'
        : 'Comparé à : '
              '${a == null ? revenueCompareName(query.compare) : (revenueComparisonLabel(a) ?? revenueCompareName(query.compare))}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The five wrap rather than scroll: at the default text size a
        // 360–390dp phone has no room for all of them on one line, and a
        // sideways row hid « Dates… » past the edge (§4.3, §4.12 — every
        // choice in sight, at any text size).
        Wrap(
          spacing: AppTheme.spacingS,
          runSpacing: AppTheme.spacingS,
          children: [
            for (final e in _names.entries)
              AppChip.choice(
                label: e.value,
                selected: query.period == e.key,
                onSelected: (_) {
                  if (query.period != e.key) onPeriod(e.key);
                },
              ),
            AppChip.choice(
              label: 'Dates…',
              selected: query.period == RevenuePeriod.custom,
              onSelected: (_) => onCustom(),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingS),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Période précédente',
              onPressed: previous == null ? null : () => onStep(previous),
            ),
            Expanded(
              child: Column(
                children: [
                  Semantics(
                    header: true,
                    headingLevel: 2,
                    liveRegion: true,
                    child: Text(
                      title ?? '',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (a != null && a.inProgress)
                    Text(
                      '(en cours)',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Période suivante',
              onPressed: next == null ? null : () => onStep(next),
            ),
          ],
        ),
        Center(
          child: TextButton(
            onPressed: onCompare,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: compare),
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.arrow_drop_down, size: AppTheme.iconS),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

/// One row of « Répartition » (§4.7): the label (wraps, never truncated) and
/// its amount, the share bar, « {n} rdv · panier {montant} · {part} % » and
/// the delta — one semantics node, the whole card the target.
class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.axis,
    required this.row,
    required this.currency,
    required this.comparison,
    required this.onTap,
  });

  final RevenueAxis axis;
  final RevenueRow row;
  final String currency;
  final String? comparison;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    String money(double v) => Formatters.formatCurrency(v, currency: currency);
    final label = revenueLabelOf(axis, row);
    final cur = row.current;
    final amount = money(cur.completedAmount);
    final shown = row.estimated ? '$amount · estimé' : amount;
    final share = Formatters.formatPercent(row.share);
    final avg = cur.averageTicket;
    final meta = [
      '${cur.completedCount} rdv',
      if (avg != null) 'panier ${money(avg)}',
      share,
    ].join(' · ');
    final delta = revenueDelta(
      cur.completedAmount,
      row.previous?.completedAmount,
      comparison: comparison,
    );
    final spoken = [
      label,
      shown,
      '$share du réalisé',
      Formatters.count(cur.completedCount, 'rendez-vous', 'rendez-vous'),
      if (avg != null) 'panier moyen ${money(avg)}',
      ?delta?.spoken,
    ].join(', ');

    return AppCard(
      onTap: onTap,
      child: Semantics(
        label: onTap == null ? '$spoken.' : '$spoken. Ouvrir le détail.',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LabelValueRow(
              label: label,
              value: shown,
              labelStyle: AppTextStyles.titleSmall.copyWith(
                color: AppColors.textPrimary,
              ),
              valueStyle: AppTextStyles.titleSmall.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppTheme.spacingS),
            ShareBar(share: row.share),
            const SizedBox(height: AppTheme.spacingS),
            Wrap(
              spacing: AppTheme.spacingS,
              runSpacing: AppTheme.spacingXS,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  meta,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (delta != null) DeltaBadge(delta),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One segment per currency (§4.11) — nothing adds two currencies.
class _CurrencySwitch extends StatelessWidget {
  const _CurrencySwitch({
    required this.groups,
    required this.selected,
    required this.onSelected,
  });

  final List<RevenueGroup> groups;
  final String selected;
  final ValueChanged<String> onSelected;

  static String nameOf(String code) => switch (code) {
    'XOF' => 'XOF · franc CFA (UEMOA)',
    'XAF' => 'XAF · franc CFA (CEMAC)',
    _ => code,
  };

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppTheme.spacingS,
    runSpacing: AppTheme.spacingS,
    children: [
      for (final g in groups)
        AppChip.choice(
          label: nameOf(g.currency),
          selected: g.currency == selected,
          onSelected: (_) => onSelected(g.currency),
        ),
    ],
  );
}

/// The first load's shape (§4.11): the figure tiles, a chart block and
/// three rows, on cards — one label for screen readers.
class _RevenueSkeleton extends StatelessWidget {
  const _RevenueSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget tile() => const Expanded(
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBar(widthFactor: 0.5),
            SizedBox(height: AppTheme.spacingS),
            SkeletonBar(widthFactor: 0.8),
          ],
        ),
      ),
    );
    Widget pair() => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile(),
          const SizedBox(width: AppTheme.spacingSM),
          tile(),
        ],
      ),
    );
    return AppSkeleton(
      label: 'Chargement des revenus…',
      child: Column(
        children: [
          pair(),
          const SizedBox(height: AppTheme.spacingSM),
          pair(),
          const SizedBox(height: AppTheme.spacingL),
          const AppCard(child: SkeletonBlock(height: BarSeries.height)),
          const SizedBox(height: AppTheme.spacingL),
          for (var i = 0; i < 3; i++) ...[
            const AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBar(widthFactor: 0.6),
                  SizedBox(height: AppTheme.spacingS),
                  SkeletonBar(widthFactor: 0.9),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.spacingS),
          ],
        ],
      ),
    );
  }
}

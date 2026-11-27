import 'package:equatable/equatable.dart';

/// The salon's revenue analytics (module `analytics`) — the app's half of
/// docs/design/pro-revenue-analytics.md: the query it sends (§3.5, §7.1) and
/// the answers it draws (`RevenueAnalytics`, `RevenueLedgerPage` in
/// docs/api/openapi.yaml), field for field.
///
/// **The server owns every definition** (§3): the period's dates, the
/// comparison, the buckets, the figures, the labels. Nothing here computes a
/// figure; the one piece of arithmetic is the calendar step of ‹ › (§3.5:
/// « date arithmetic on a date, no clock involved »), in [RevenueQuery].
///
/// **Strict, as #630 asks**: every field the contract marks required is read
/// with a cast, so a body without its parts throws and the service turns it
/// into `unreadable` (`readOrUnreadable`) — never a screen of zeros. An enum
/// value the app does not know is the same: a new value is a contract change.

// ── Calendar dates ──────────────────────────────────────────────────────────

/// A salon calendar date — a day, not an instant: `DateTime.utc(y, m, d)`,
/// the backend's `revenueDate`. Never compared with a clock.
DateTime revenueDay(int year, int month, int day) =>
    DateTime.utc(year, month, day);

final RegExp _dayPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// `2026-11-25` → the day. Anything else throws [FormatException].
DateTime parseRevenueDay(Object? value) {
  final match = value is String ? _dayPattern.firstMatch(value) : null;
  if (match == null) throw FormatException('not a YYYY-MM-DD date', value);
  final d = revenueDay(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  // 2026-02-30 would roll to March: refused, not reinterpreted.
  if (revenueDayKey(d) != value) {
    throw FormatException('not a calendar date', value);
  }
  return d;
}

/// The day → `2026-11-25`.
String revenueDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// [d] moved by [days] calendar days (no daylight-saving drift: UTC dates).
DateTime addRevenueDays(DateTime d, int days) =>
    DateTime.utc(d.year, d.month, d.day + days);

/// The number of calendar days from [a] to [b] (b − a).
int revenueDaysBetween(DateTime a, DateTime b) => b.difference(a).inDays;

/// The first day the server accepts (§3.5 « Bounds »).
final DateTime kRevenueEarliestDay = revenueDay(2020, 1, 1);

/// The longest range, and how far ahead a date may be (§3.5, §11).
const int kRevenueMaxDays = 366;

DateTime _instant(Object? value) {
  if (value is! String) throw FormatException('not a date-time', value);
  return DateTime.parse(value).toUtc();
}

T _enum<T extends Enum>(List<T> values, Object? name) => values.firstWhere(
  (v) => v.name == name,
  orElse: () => throw FormatException('unknown ${T.toString()}', name),
);

double _amount(Object? v) => (v as num).toDouble();
double? _amountOrNull(Object? v) => v == null ? null : (v as num).toDouble();

// ── The query ───────────────────────────────────────────────────────────────

enum RevenuePeriod { day, week, month, year, custom }

enum RevenueCompare { previous, year, none }

enum RevenueBucket { day, week, month }

/// How a booking was made (§3.3 « Par canal »). `online` = an online booking
/// made before the channel was recorded (app or website, unknown).
enum RevenueChannel { app, web, salon, online }

/// A row's state (§3.3's labels table).
enum RevenueRowState { active, removed, unassigned, legacy }

/// The three breakdowns (§4.7).
enum RevenueAxis { artist, service, channel }

/// The ledger's filters (§4.9, §7.2 `status`).
enum RevenueLedgerStatus { completed, upcoming, toClose, noShow, cancelled }

/// One period, its comparison and its filter: what « Revenus » and its
/// details ask the server (§7.1). Calendar dates only — [date], [from], [to]
/// are salon days; no [date] means the salon's today **as the server reads
/// it**, so a phone whose clock is wrong still opens on the right month.
class RevenueQuery extends Equatable {
  const RevenueQuery({
    this.period = RevenuePeriod.month,
    this.date,
    this.from,
    this.to,
    this.compare = RevenueCompare.previous,
    this.artistId,
    this.serviceId,
    this.channel,
  }) : assert(
         period == RevenuePeriod.custom
             ? (from != null && to != null && date == null)
             : (from == null && to == null),
         'custom takes from + to; the others take an optional date',
       );

  final RevenuePeriod period;
  final DateTime? date;
  final DateTime? from;
  final DateTime? to;
  final RevenueCompare compare;

  /// A collaborateur's id, or [kNoArtist] for the bookings without one.
  final String? artistId;
  final String? serviceId;
  final RevenueChannel? channel;

  /// The `artistId` that asks for the bookings with no collaborateur (§7.1).
  static const String kNoArtist = 'none';

  /// The filter this query carries, if any — the detail it belongs to.
  RevenueAxis? get filterAxis => artistId != null
      ? RevenueAxis.artist
      : serviceId != null
      ? RevenueAxis.service
      : channel != null
      ? RevenueAxis.channel
      : null;

  /// The same filter on another period or comparison.
  RevenueQuery withPeriod({
    required RevenuePeriod period,
    DateTime? date,
    DateTime? from,
    DateTime? to,
  }) => RevenueQuery(
    period: period,
    date: date,
    from: from,
    to: to,
    compare: compare,
    artistId: artistId,
    serviceId: serviceId,
    channel: channel,
  );

  RevenueQuery withCompare(RevenueCompare compare) => RevenueQuery(
    period: period,
    date: date,
    from: from,
    to: to,
    compare: compare,
    artistId: artistId,
    serviceId: serviceId,
    channel: channel,
  );

  /// This period, filtered on one row of [axis] (a detail's query, §4.8).
  /// A null [key] on the collaborateur axis is « Sans collaborateur ».
  RevenueQuery filteredOn(RevenueAxis axis, String? key) => RevenueQuery(
    period: period,
    date: date,
    from: from,
    to: to,
    compare: compare,
    artistId: axis == RevenueAxis.artist ? (key ?? kNoArtist) : null,
    serviceId: axis == RevenueAxis.service ? key : null,
    channel: axis == RevenueAxis.channel
        ? _enum(RevenueChannel.values, key)
        : null,
  );

  /// The query string of `GET /providers/{id}/analytics/revenue` (§7.1).
  Map<String, String> toQueryParameters() => {
    'period': period.name,
    if (date case final d?) 'date': revenueDayKey(d),
    if (from case final f?) 'from': revenueDayKey(f),
    if (to case final t?) 'to': revenueDayKey(t),
    'compare': compare.name,
    'artistId': ?artistId,
    'serviceId': ?serviceId,
    if (channel case final c?) 'channel': c.name,
  };

  /// The period in a route's query (`?period=month&date=…&compare=…`, §4.1):
  /// the filter lives in the path, so Back returns to the same period.
  Map<String, String> toRouteQuery() => {
    'period': period.name,
    if (date case final d?) 'date': revenueDayKey(d),
    if (from case final f?) 'from': revenueDayKey(f),
    if (to case final t?) 'to': revenueDayKey(t),
    'compare': compare.name,
  };

  /// A route's query back to a period. Anything malformed falls back to the
  /// current month (no date: the server's today), never to an error page.
  static RevenueQuery fromRouteQuery(
    Map<String, String> query, {
    String? artistId,
    String? serviceId,
    RevenueChannel? channel,
  }) {
    DateTime? day(String key) {
      final v = query[key];
      if (v == null) return null;
      try {
        return parseRevenueDay(v);
      } on FormatException {
        return null;
      }
    }

    final period = RevenuePeriod.values
        .where((p) => p.name == query['period'])
        .firstOrNull;
    final compare =
        RevenueCompare.values
            .where((c) => c.name == query['compare'])
            .firstOrNull ??
        RevenueCompare.previous;
    final base = RevenueQuery(
      compare: compare,
      artistId: artistId,
      serviceId: serviceId,
      channel: channel,
    );
    switch (period) {
      case null:
        return base;
      case RevenuePeriod.custom:
        final f = day('from');
        final t = day('to');
        if (f == null || t == null || t.isBefore(f)) return base;
        if (revenueDaysBetween(f, t) + 1 > kRevenueMaxDays) return base;
        return base.withPeriod(period: period, from: f, to: t);
      default:
        return base.withPeriod(period: period, date: day('date'));
    }
  }

  @override
  List<Object?> get props => [
    period,
    date,
    from,
    to,
    compare,
    artistId,
    serviceId,
    channel,
  ];
}

// ── The answer ──────────────────────────────────────────────────────────────

/// `GET /providers/{id}/analytics/revenue` (§7.1).
class RevenueAnalytics extends Equatable {
  const RevenueAnalytics({
    required this.period,
    required this.from,
    required this.to,
    required this.inProgress,
    required this.timezone,
    required this.asOf,
    required this.bucket,
    required this.comparison,
    required this.filters,
    required this.everCompleted,
    required this.groups,
  });

  final RevenuePeriod period;

  /// The resolved first and last day, salon calendar.
  final DateTime from;
  final DateTime to;

  /// The salon's today is inside [from]–[to].
  final bool inProgress;

  /// The salon's IANA zone.
  final String timezone;

  /// The server's « now » for this answer — what « Prévu » and « À
  /// clôturer » are measured against; the ledger is asked with it (§7.2).
  final DateTime asOf;
  final RevenueBucket bucket;
  final RevenueComparison comparison;
  final RevenueFilters filters;

  /// The salon has at least one completed booking, ever (§4.11).
  final bool everCompleted;

  /// One per currency, the salon's own first; `[]` = nothing in either range.
  final List<RevenueGroup> groups;

  /// The number of days in the period.
  int get days => revenueDaysBetween(from, to) + 1;

  /// The group of [currency], or the first (the salon's own).
  RevenueGroup? groupFor(String? currency) {
    for (final g in groups) {
      if (g.currency == currency) return g;
    }
    return groups.firstOrNull;
  }

  factory RevenueAnalytics.fromJson(Map<String, dynamic> json) =>
      RevenueAnalytics(
        period: _enum(RevenuePeriod.values, json['period']),
        from: parseRevenueDay(json['from']),
        to: parseRevenueDay(json['to']),
        inProgress: json['inProgress'] as bool,
        timezone: json['timezone'] as String,
        asOf: _instant(json['asOf']),
        bucket: _enum(RevenueBucket.values, json['bucket']),
        comparison: RevenueComparison.fromJson(
          (json['comparison'] as Map).cast<String, dynamic>(),
        ),
        filters: RevenueFilters.fromJson(
          (json['filters'] as Map).cast<String, dynamic>(),
        ),
        everCompleted: json['everCompleted'] as bool,
        groups: [
          for (final g in json['groups'] as List)
            RevenueGroup.fromJson((g as Map).cast<String, dynamic>()),
        ],
      );

  @override
  List<Object?> get props => [
    period,
    from,
    to,
    inProgress,
    timezone,
    asOf,
    bucket,
    comparison,
    filters,
    everCompleted,
    groups,
  ];
}

class RevenueComparison extends Equatable {
  const RevenueComparison({
    required this.mode,
    this.from,
    this.to,
    this.likeForLike = false,
    this.cutoff,
  });

  final RevenueCompare mode;
  final DateTime? from;
  final DateTime? to;

  /// The current period is in progress, so the comparison stops at the same
  /// point of its own period (§3.5): [cutoff].
  final bool likeForLike;
  final DateTime? cutoff;

  factory RevenueComparison.fromJson(Map<String, dynamic> json) {
    final cutoff = json['cutoff'];
    return RevenueComparison(
      mode: _enum(RevenueCompare.values, json['mode']),
      from: json['from'] == null ? null : parseRevenueDay(json['from']),
      to: json['to'] == null ? null : parseRevenueDay(json['to']),
      likeForLike: json['likeForLike'] as bool,
      cutoff: cutoff == null ? null : _instant(cutoff),
    );
  }

  @override
  List<Object?> get props => [mode, from, to, likeForLike, cutoff];
}

class RevenueFilters extends Equatable {
  const RevenueFilters({
    this.artistId,
    this.serviceId,
    this.channel,
    this.label,
    this.state,
  });

  final String? artistId;
  final String? serviceId;
  final String? channel;

  /// The filtered row's label (§3.3); null → the generic one.
  final String? label;
  final RevenueRowState? state;

  factory RevenueFilters.fromJson(Map<String, dynamic> json) => RevenueFilters(
    artistId: json['artistId'] as String?,
    serviceId: json['serviceId'] as String?,
    channel: json['channel'] as String?,
    label: json['label'] as String?,
    state: json['state'] == null
        ? null
        : _enum(RevenueRowState.values, json['state']),
  );

  @override
  List<Object?> get props => [artistId, serviceId, channel, label, state];
}

/// One currency's figures — never added to another's (§2.5).
class RevenueGroup extends Equatable {
  const RevenueGroup({
    required this.currency,
    required this.current,
    this.previous,
    this.series = const [],
    this.byArtist = const [],
    this.byService = const [],
    this.byChannel = const [],
  });

  /// ISO 4217.
  final String currency;
  final RevenueFigures current;

  /// The comparison's figures; null with « Aucune comparaison ».
  final RevenueFigures? previous;

  /// One point per bucket of the current range, zero-filled.
  final List<RevenueSeriesPoint> series;
  final List<RevenueRow> byArtist;
  final List<RevenueRow> byService;
  final List<RevenueRow> byChannel;

  List<RevenueRow> rowsOf(RevenueAxis axis) => switch (axis) {
    RevenueAxis.artist => byArtist,
    RevenueAxis.service => byService,
    RevenueAxis.channel => byChannel,
  };

  factory RevenueGroup.fromJson(Map<String, dynamic> json) {
    List<RevenueRow> rows(String key) => [
      for (final r in json[key] as List)
        RevenueRow.fromJson((r as Map).cast<String, dynamic>()),
    ];
    final previous = json['previous'];
    return RevenueGroup(
      currency: json['currency'] as String,
      current: RevenueFigures.fromJson(
        (json['current'] as Map).cast<String, dynamic>(),
      ),
      previous: previous == null
          ? null
          : RevenueFigures.fromJson((previous as Map).cast<String, dynamic>()),
      series: [
        for (final p in json['series'] as List)
          RevenueSeriesPoint.fromJson((p as Map).cast<String, dynamic>()),
      ],
      byArtist: rows('byArtist'),
      byService: rows('byService'),
      byChannel: rows('byChannel'),
    );
  }

  @override
  List<Object?> get props => [
    currency,
    current,
    previous,
    series,
    byArtist,
    byService,
    byChannel,
  ];
}

class RevenueSeriesPoint extends Equatable {
  const RevenueSeriesPoint({
    required this.start,
    required this.end,
    required this.completedAmount,
    required this.completedCount,
  });

  final DateTime start;
  final DateTime end;
  final double completedAmount;
  final int completedCount;

  factory RevenueSeriesPoint.fromJson(Map<String, dynamic> json) =>
      RevenueSeriesPoint(
        start: parseRevenueDay(json['start']),
        end: parseRevenueDay(json['end']),
        completedAmount: _amount(json['completedAmount']),
        completedCount: (json['completedCount'] as num).toInt(),
      );

  @override
  List<Object?> get props => [start, end, completedAmount, completedCount];
}

/// The figures of one period (§3.2).
class RevenueFigures extends Equatable {
  const RevenueFigures({
    this.completedAmount = 0,
    this.completedCount = 0,
    this.averageTicket,
    this.upcomingAmount = 0,
    this.upcomingCount = 0,
    this.pendingAmount = 0,
    this.pendingCount = 0,
    this.toCloseAmount = 0,
    this.toCloseCount = 0,
    this.noShowAmount = 0,
    this.noShowCount = 0,
    this.noShowRate,
    this.cancelledAmount = 0,
    this.cancelledCount = 0,
    this.estimated = false,
  });

  /// « Réalisé » — completed bookings.
  final double completedAmount;
  final int completedCount;

  /// « Panier moyen »; null with no completed booking.
  final double? averageTicket;

  /// « Prévu » — confirmed bookings whose end is `asOf` or later.
  final double upcomingAmount;
  final int upcomingCount;

  /// Requests (`pending`) whose start is `asOf` or later.
  final double pendingAmount;
  final int pendingCount;

  /// « À clôturer » — confirmed bookings whose end is before `asOf`.
  final double toCloseAmount;
  final int toCloseCount;
  final double noShowAmount;
  final int noShowCount;

  /// 0–1; null when no booking was completed or missed.
  final double? noShowRate;
  final double cancelledAmount;
  final int cancelledCount;

  /// Some completed amount here rests on an estimated line (§3.4).
  final bool estimated;

  factory RevenueFigures.fromJson(Map<String, dynamic> json) => RevenueFigures(
    completedAmount: _amount(json['completedAmount']),
    completedCount: (json['completedCount'] as num).toInt(),
    averageTicket: _amountOrNull(json['averageTicket']),
    upcomingAmount: _amount(json['upcomingAmount']),
    upcomingCount: (json['upcomingCount'] as num).toInt(),
    pendingAmount: _amount(json['pendingAmount']),
    pendingCount: (json['pendingCount'] as num).toInt(),
    toCloseAmount: _amount(json['toCloseAmount']),
    toCloseCount: (json['toCloseCount'] as num).toInt(),
    noShowAmount: _amount(json['noShowAmount']),
    noShowCount: (json['noShowCount'] as num).toInt(),
    noShowRate: _amountOrNull(json['noShowRate']),
    cancelledAmount: _amount(json['cancelledAmount']),
    cancelledCount: (json['cancelledCount'] as num).toInt(),
    estimated: json['estimated'] as bool,
  );

  @override
  List<Object?> get props => [
    completedAmount,
    completedCount,
    averageTicket,
    upcomingAmount,
    upcomingCount,
    pendingAmount,
    pendingCount,
    toCloseAmount,
    toCloseCount,
    noShowAmount,
    noShowCount,
    noShowRate,
    cancelledAmount,
    cancelledCount,
    estimated,
  ];
}

/// One collaborateur, prestation or channel (§3.3).
class RevenueRow extends Equatable {
  const RevenueRow({
    required this.key,
    required this.label,
    required this.state,
    required this.share,
    required this.current,
    this.previous,
    this.estimated = false,
  });

  /// The artistId, serviceId or channel; null = no collaborateur.
  final String? key;

  /// The live name, else the kept one; null → the generic label.
  final String? label;
  final RevenueRowState state;

  /// Of the group's « Réalisé », 0–1; the shares of one axis add up to 1.
  final double share;
  final RevenueRowFigures current;
  final RevenueRowFigures? previous;

  /// Its current or previous amount rests on an estimated line (§3.4).
  final bool estimated;

  factory RevenueRow.fromJson(Map<String, dynamic> json) {
    final previous = json['previous'];
    return RevenueRow(
      key: json['key'] as String?,
      label: json['label'] as String?,
      state: _enum(RevenueRowState.values, json['state']),
      share: _amount(json['share']),
      current: RevenueRowFigures.fromJson(
        (json['current'] as Map).cast<String, dynamic>(),
      ),
      previous: previous == null
          ? null
          : RevenueRowFigures.fromJson(
              (previous as Map).cast<String, dynamic>(),
            ),
      estimated: json['estimated'] as bool,
    );
  }

  @override
  List<Object?> get props => [
    key,
    label,
    state,
    share,
    current,
    previous,
    estimated,
  ];
}

class RevenueRowFigures extends Equatable {
  const RevenueRowFigures({
    this.completedAmount = 0,
    this.completedCount = 0,
    this.averageTicket,
  });

  final double completedAmount;
  final int completedCount;
  final double? averageTicket;

  factory RevenueRowFigures.fromJson(Map<String, dynamic> json) =>
      RevenueRowFigures(
        completedAmount: _amount(json['completedAmount']),
        completedCount: (json['completedCount'] as num).toInt(),
        averageTicket: _amountOrNull(json['averageTicket']),
      );

  @override
  List<Object?> get props => [completedAmount, completedCount, averageTicket];
}

// ── The ledger ──────────────────────────────────────────────────────────────

/// `GET /providers/{id}/analytics/revenue/appointments` (§7.2): one page.
class RevenueLedgerPage extends Equatable {
  const RevenueLedgerPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.asOf,
  });

  final List<RevenueLedgerRow> items;
  final int page;
  final int pageSize;
  final int total;

  /// The instant `upcoming` and `toClose` were measured against.
  final DateTime asOf;

  factory RevenueLedgerPage.fromJson(Map<String, dynamic> json) =>
      RevenueLedgerPage(
        items: [
          for (final r in json['items'] as List)
            RevenueLedgerRow.fromJson((r as Map).cast<String, dynamic>()),
        ],
        page: (json['page'] as num).toInt(),
        pageSize: (json['pageSize'] as num).toInt(),
        total: (json['total'] as num).toInt(),
        asOf: _instant(json['asOf']),
      );

  @override
  List<Object?> get props => [items, page, pageSize, total, asOf];
}

/// One booking behind a figure.
class RevenueLedgerRow extends Equatable {
  const RevenueLedgerRow({
    required this.appointmentId,
    required this.appointmentDate,
    required this.status,
    required this.amount,
    required this.totalPrice,
    required this.currency,
    this.clientDisplayName,
    this.serviceNames = const [],
    this.artistLabel,
    required this.artistState,
    required this.channel,
    this.estimated = false,
  });

  final String appointmentId;

  /// The start, an instant (UTC) — shown in salon time.
  final DateTime appointmentDate;

  /// The stored status: `completed`, `confirmed`, `noShow`, `cancelled`.
  final String status;

  /// The prestation's lines under a `serviceId` filter; else [totalPrice].
  final double amount;
  final double totalPrice;
  final String currency;

  /// The salon's name for the client; absent without `clients.view`, or when
  /// no client resolves (an erased one) — the screen reads « Client ».
  final String? clientDisplayName;

  /// One per prestation line, in order; null = deleted, no kept name.
  final List<String?> serviceNames;
  final String? artistLabel;
  final RevenueRowState artistState;
  final RevenueChannel channel;

  /// [amount] rests on an estimated line.
  final bool estimated;

  factory RevenueLedgerRow.fromJson(Map<String, dynamic> json) =>
      RevenueLedgerRow(
        appointmentId: json['appointmentId'] as String,
        appointmentDate: _instant(json['appointmentDate']),
        status: json['status'] as String,
        amount: _amount(json['amount']),
        totalPrice: _amount(json['totalPrice']),
        currency: json['currency'] as String,
        clientDisplayName: json['clientDisplayName'] as String?,
        serviceNames: (json['serviceNames'] as List).cast<String?>(),
        artistLabel: json['artistLabel'] as String?,
        artistState: _enum(RevenueRowState.values, json['artistState']),
        channel: _enum(RevenueChannel.values, json['channel']),
        estimated: json['estimated'] as bool,
      );

  @override
  List<Object?> get props => [
    appointmentId,
    appointmentDate,
    status,
    amount,
    totalPrice,
    currency,
    clientDisplayName,
    serviceNames,
    artistLabel,
    artistState,
    channel,
    estimated,
  ];
}

import 'dart:math' as math;

import '../../core/utils/salon_id.dart';
import '../../core/utils/salon_time.dart';
import '../../models/revenue_analytics.dart';
import 'mock_data.dart';

/// The mock world of « Revenus » (docs/design/pro-revenue-analytics.md §7.4):
/// a salon with a history, folded by the server's rules (§3) so the screens
/// can be built and tested with no backend.
///
/// **What it holds** — `provider1` only (every other salon is the « Pas
/// encore de revenus » salon): about fourteen months of bookings, made
/// deterministically from each day's date (the same day always holds the
/// same bookings, whatever the clock), with
/// - the salon's two collaborateurs, one who left the team (a name kept
///   from after the channel was recorded) and bookings with none;
/// - its three prestations, one deleted with its name kept and one deleted
///   before names were kept (« Prestation supprimée »);
/// - every channel: the app and the website after the « recording » day,
///   « En ligne (avant le suivi) » before it, the salon's own throughout;
/// - two-prestation bookings before that day, so a prestation row reads
///   « estimé »;
/// - [twoCurrencies] (a debug switch) puts every seventh booking in XAF.
///
/// **The mock's R1** is [_recordingDays] before today, not the real
/// 26 November 2026: tests freeze the clock in March 2026, and a fixed date
/// would leave the frozen world with no recorded channel at all.
///
/// The salon is in Abidjan (UTC+0), so its days are UTC days: the fold
/// below reads dates in UTC and says [kSalonTz].
class MockRevenueWorld {
  MockRevenueWorld._();

  /// Debug: the next read fails once, as a dropped connection would.
  static bool failNext = false;

  /// Debug: some bookings in XAF — the currency switcher (§4.11).
  static bool twoCurrencies = false;

  static const SalonId salonWithHistory = SalonId('provider1');

  static const int _historyDays = 430;
  static const int _futureDays = 45;
  static const int _recordingDays = 60;

  /// Built once per salon day and switch: the fold reads it, never mutates.
  static final Map<String, List<_Booking>> _cache = {};

  static List<_Booking> _bookings(SalonId salon, DateTime now) {
    if (salon != salonWithHistory) return const [];
    final today = _day(now);
    final key = '${revenueDayKey(today)}|$twoCurrencies';
    return _cache.putIfAbsent(key, () {
      _cache.clear();
      return _generate(today);
    });
  }

  // ── The world ─────────────────────────────────────────────────────────────

  static const _clients = [
    'Fatou B.',
    'Yao K.',
    'Mariam T.',
    'Ibrahim S.',
    'Adjoua N.',
    'Koffi A.',
    'Aminata D.',
    'Serge K.',
  ];

  static List<_Booking> _generate(DateTime today) {
    final recorded = addRevenueDays(today, -_recordingDays);
    final artistLeft = addRevenueDays(today, -20);
    final keptServiceGone = addRevenueDays(today, -30);
    final unnamedServiceGone = addRevenueDays(today, -_recordingDays - 30);
    final out = <_Booking>[];
    var n = 0;
    for (var i = -_historyDays; i <= _futureDays; i++) {
      final day = addRevenueDays(today, i);
      if (day.weekday == DateTime.sunday) continue;
      final rnd = math.Random(day.year * 10000 + day.month * 100 + day.day);
      final count = rnd.nextInt(4) + (day.weekday == DateTime.saturday ? 1 : 0);
      for (var k = 0; k < count; k++) {
        n++;
        final start = DateTime.utc(
          day.year,
          day.month,
          day.day,
          9 + rnd.nextInt(9),
          rnd.nextBool() ? 0 : 30,
        );
        final a = rnd.nextInt(10);
        final artist = a < 4
            ? 'artist1'
            : a < 7
            ? 'artist2'
            : a == 7 && day.isBefore(artistLeft)
            ? 'artist_parti'
            : null;
        final s = rnd.nextInt(10);
        final services = switch (s) {
          < 4 => ['service1'],
          < 6 => ['service2'],
          < 8 => ['service3'],
          8 => ['service1', 'service2'],
          _ =>
            day.isBefore(unnamedServiceGone)
                ? ['service_defrisage']
                : day.isBefore(keptServiceGone)
                ? ['service_nattes']
                : ['service1'],
        };
        final c = rnd.nextInt(10);
        final online = c < 6;
        final channel = !online
            ? RevenueChannel.salon
            : day.isBefore(recorded)
            ? RevenueChannel.online
            : (c < 4 ? RevenueChannel.app : RevenueChannel.web);
        final st = rnd.nextInt(100);
        final past = i < 0 || (i == 0 && start.hour < 10);
        final String status;
        if (past) {
          status = st < 6
              ? 'noShow'
              : st < 11
              ? 'cancelled'
              : (st < 16 && i >= -6)
              ? 'confirmed' // nobody closed it: « À clôturer »
              : 'completed';
        } else {
          status = st < 20
              ? 'pending'
              : st < 26
              ? 'cancelled'
              : 'confirmed';
        }
        final lines = [for (final id in services) _price(id)];
        out.add(
          _Booking(
            id: 'mock_rev_${revenueDayKey(day)}_$k',
            start: start,
            minutes: 30 + 15 * services.length,
            status: status,
            artistId: artist,
            artistNameKept: day.isBefore(recorded) || artist == null
                ? null
                : _artistNames[artist],
            serviceIds: services,
            lines: lines,
            serviceNamesKept: day.isBefore(recorded)
                ? null
                : [for (final id in services) _serviceNames[id]],
            estimated: day.isBefore(recorded) && services.length > 1,
            currency: twoCurrencies && n % 7 == 0 ? 'XAF' : 'XOF',
            channel: channel,
            client: _clients[rnd.nextInt(_clients.length)],
          ),
        );
      }
    }
    return out;
  }

  static const _artistNames = {
    'artist1': 'Kouassi Jean',
    'artist2': 'Diallo Amadou',
    'artist_parti': 'Konan Serge',
  };

  static const _serviceNames = {
    'service1': 'Coupe Homme',
    'service2': 'Rasage',
    'service3': 'Coupe + Rasage',
    'service_nattes': 'Nattes',
    'service_defrisage': 'Défrisage',
  };

  static double _price(String serviceId) => switch (serviceId) {
    'service1' => 5000,
    'service2' => 3000,
    'service3' => 7000,
    'service_nattes' => 6000,
    _ => 8000,
  };

  static Map<String, String> _liveArtists(SalonId salon) => {
    for (final a in MockData.getArtistsForProvider(salon)) a.id: a.name,
  };

  static Map<String, String> _liveServices(SalonId salon) => {
    for (final s in MockData.getServicesForProvider(salon)) s.id: s.name,
  };

  // ── The fold (§3) ─────────────────────────────────────────────────────────

  static DateTime _day(DateTime instant) {
    final u = instant.toUtc();
    return revenueDay(u.year, u.month, u.day);
  }

  static RevenueDayRange _rangeOf(RevenuePeriod p, DateTime d) {
    switch (p) {
      case RevenuePeriod.day:
        return RevenueDayRange(d, d);
      case RevenuePeriod.week:
        final monday = addRevenueDays(d, -(d.weekday - DateTime.monday));
        return RevenueDayRange(monday, addRevenueDays(monday, 6));
      case RevenuePeriod.month:
        return RevenueDayRange(
          revenueDay(d.year, d.month, 1),
          revenueDay(d.year, d.month + 1, 0),
        );
      case RevenuePeriod.year:
        return RevenueDayRange(
          revenueDay(d.year, 1, 1),
          revenueDay(d.year, 12, 31),
        );
      case RevenuePeriod.custom:
        throw ArgumentError('custom has no date range');
    }
  }

  static DateTime _yearEarlier(DateTime d) {
    final last = revenueDay(d.year - 1, d.month + 1, 0).day;
    return revenueDay(d.year - 1, d.month, math.min(d.day, last));
  }

  static RevenueDayRange? _comparisonOf(
    RevenuePeriod p,
    RevenueCompare c,
    RevenueDayRange r,
  ) {
    switch (c) {
      case RevenueCompare.none:
        return null;
      case RevenueCompare.previous:
        return switch (p) {
          RevenuePeriod.day => RevenueDayRange(
            addRevenueDays(r.from, -1),
            addRevenueDays(r.to, -1),
          ),
          RevenuePeriod.week => RevenueDayRange(
            addRevenueDays(r.from, -7),
            addRevenueDays(r.to, -7),
          ),
          RevenuePeriod.month => RevenueDayRange(
            revenueDay(r.from.year, r.from.month - 1, 1),
            addRevenueDays(r.from, -1),
          ),
          RevenuePeriod.year => RevenueDayRange(
            revenueDay(r.from.year - 1, 1, 1),
            revenueDay(r.from.year - 1, 12, 31),
          ),
          RevenuePeriod.custom => RevenueDayRange(
            addRevenueDays(r.from, -r.days),
            addRevenueDays(r.from, -1),
          ),
        };
      case RevenueCompare.year:
        return switch (p) {
          RevenuePeriod.week => RevenueDayRange(
            addRevenueDays(r.from, -364),
            addRevenueDays(r.to, -364),
          ),
          RevenuePeriod.month => RevenueDayRange(
            revenueDay(r.from.year - 1, r.from.month, 1),
            revenueDay(r.from.year - 1, r.from.month + 1, 0),
          ),
          RevenuePeriod.year => RevenueDayRange(
            revenueDay(r.from.year - 1, 1, 1),
            revenueDay(r.from.year - 1, 12, 31),
          ),
          _ => RevenueDayRange(_yearEarlier(r.from), _yearEarlier(r.to)),
        };
    }
  }

  /// The period of [q] at [now], or the server's refusal code.
  static ({_Period? period, String? error}) _resolve(
    RevenueQuery q,
    DateTime now,
  ) {
    final today = _day(now);
    final latest = addRevenueDays(today, kRevenueMaxDays);
    bool inBounds(DateTime d) =>
        !d.isBefore(kRevenueEarliestDay) && !d.isAfter(latest);
    final RevenueDayRange range;
    if (q.period == RevenuePeriod.custom) {
      final f = q.from!;
      final t = q.to!;
      if (!inBounds(f) || !inBounds(t) || t.isBefore(f)) {
        return (period: null, error: 'invalid_input');
      }
      range = RevenueDayRange(f, t);
      if (range.days > kRevenueMaxDays) {
        return (period: null, error: 'range_too_long');
      }
    } else {
      final d = q.date ?? today;
      if (!inBounds(d)) return (period: null, error: 'invalid_input');
      range = _rangeOf(q.period, d);
    }
    final comparison = _comparisonOf(q.period, q.compare, range);
    final inProgress = range.contains(today);
    DateTime? cutoff;
    if (comparison != null && inProgress) {
      final cutDay = addRevenueDays(
        comparison.from,
        revenueDaysBetween(range.from, today),
      );
      final u = now.toUtc();
      cutoff = cutDay.isAfter(comparison.to)
          ? addRevenueDays(comparison.to, 1)
          : DateTime.utc(
              cutDay.year,
              cutDay.month,
              cutDay.day,
              u.hour,
              u.minute,
              u.second,
              u.millisecond,
              u.microsecond,
            );
    }
    return (
      period: _Period(
        range: range,
        comparison: comparison,
        inProgress: inProgress,
        cutoff: cutoff,
        asOf: now.toUtc(),
      ),
      error: null,
    );
  }

  static bool _matches(_Booking b, RevenueQuery q) {
    if (q.artistId case final a?) {
      if (a == RevenueQuery.kNoArtist ? b.artistId != null : b.artistId != a) {
        return false;
      }
    }
    if (q.serviceId case final s?) {
      if (!b.serviceIds.contains(s)) return false;
    }
    if (q.channel case final c?) {
      if (b.channel != c) return false;
    }
    return true;
  }

  /// The booking's amount under [q]: its lines of the filtered prestation,
  /// else its total.
  static double _amountOf(_Booking b, RevenueQuery q) {
    final s = q.serviceId;
    if (s == null) return b.total;
    var sum = 0.0;
    for (var i = 0; i < b.serviceIds.length; i++) {
      if (b.serviceIds[i] == s) sum += b.lines[i];
    }
    return sum;
  }

  static List<_Booking> _inRange(
    List<_Booking> all,
    RevenueDayRange r, {
    DateTime? cutoff,
  }) => [
    for (final b in all)
      if (r.contains(_day(b.start)) &&
          (cutoff == null || b.start.isBefore(cutoff)))
        b,
  ];

  static RevenueFigures _figures(
    List<_Booking> bs,
    RevenueQuery q,
    DateTime asOf,
  ) {
    var done = 0.0, up = 0.0, pend = 0.0, close = 0.0, miss = 0.0, can = 0.0;
    var nDone = 0, nUp = 0, nPend = 0, nClose = 0, nMiss = 0, nCan = 0;
    var estimated = false;
    for (final b in bs) {
      final amount = _amountOf(b, q);
      switch (b.status) {
        case 'completed':
          done += amount;
          nDone++;
          estimated = estimated || (q.serviceId != null && b.estimated);
        case 'confirmed':
          if (b.end.isBefore(asOf)) {
            close += amount;
            nClose++;
          } else {
            up += amount;
            nUp++;
          }
        case 'pending':
          if (!b.start.isBefore(asOf)) {
            pend += amount;
            nPend++;
          }
        case 'noShow':
          miss += amount;
          nMiss++;
        case 'cancelled':
          can += amount;
          nCan++;
      }
    }
    return RevenueFigures(
      completedAmount: done,
      completedCount: nDone,
      averageTicket: nDone == 0 ? null : (done / nDone).roundToDouble(),
      upcomingAmount: up,
      upcomingCount: nUp,
      pendingAmount: pend,
      pendingCount: nPend,
      toCloseAmount: close,
      toCloseCount: nClose,
      noShowAmount: miss,
      noShowCount: nMiss,
      noShowRate: nDone + nMiss == 0 ? null : nMiss / (nDone + nMiss),
      cancelledAmount: can,
      cancelledCount: nCan,
      estimated: estimated,
    );
  }

  /// One axis's completed parts of a booking: one per booking, or one per
  /// prestation (a prestation twice in a booking is one part, its lines
  /// summed).
  static List<({String? key, double amount, bool est})> _parts(
    _Booking b,
    RevenueAxis axis,
    RevenueQuery q,
  ) {
    switch (axis) {
      case RevenueAxis.artist:
        return [(key: b.artistId, amount: _amountOf(b, q), est: false)];
      case RevenueAxis.channel:
        return [(key: b.channel.name, amount: _amountOf(b, q), est: false)];
      case RevenueAxis.service:
        final sums = <String, double>{};
        for (var i = 0; i < b.serviceIds.length; i++) {
          sums.update(
            b.serviceIds[i],
            (v) => v + b.lines[i],
            ifAbsent: () => b.lines[i],
          );
        }
        return [
          for (final e in sums.entries)
            (key: e.key, amount: e.value, est: b.estimated),
        ];
    }
  }

  static ({String? label, RevenueRowState state}) _labelOf(
    RevenueAxis axis,
    String? key,
    SalonId salon,
    List<_Booking> both,
  ) {
    switch (axis) {
      case RevenueAxis.artist:
        if (key == null) {
          return (label: null, state: RevenueRowState.unassigned);
        }
        final live = _liveArtists(salon)[key];
        if (live != null) return (label: live, state: RevenueRowState.active);
        String? kept;
        DateTime? latest;
        for (final b in both) {
          if (b.artistId == key &&
              b.artistNameKept != null &&
              (latest == null || b.start.isAfter(latest))) {
            kept = b.artistNameKept;
            latest = b.start;
          }
        }
        return (label: kept, state: RevenueRowState.removed);
      case RevenueAxis.service:
        final live = _liveServices(salon)[key];
        if (live != null) return (label: live, state: RevenueRowState.active);
        String? kept;
        DateTime? latest;
        for (final b in both) {
          final i = b.serviceIds.indexOf(key ?? '');
          final name = i < 0 ? null : b.serviceNamesKept?[i];
          if (name != null && (latest == null || b.start.isAfter(latest))) {
            kept = name;
            latest = b.start;
          }
        }
        return (label: kept, state: RevenueRowState.removed);
      case RevenueAxis.channel:
        return (
          label: null,
          state: key == RevenueChannel.online.name
              ? RevenueRowState.legacy
              : RevenueRowState.active,
        );
    }
  }

  static List<RevenueRow> _rows(
    RevenueAxis axis,
    List<_Booking> current,
    List<_Booking>? previous,
    RevenueQuery q,
    SalonId salon,
    double total,
  ) {
    Map<String?, ({double amount, Set<String> ids, bool est})> fold(
      List<_Booking> bs,
    ) {
      final acc = <String?, ({double amount, Set<String> ids, bool est})>{};
      for (final b in bs) {
        if (b.status != 'completed') continue;
        for (final p in _parts(b, axis, q)) {
          final a = acc[p.key] ?? (amount: 0.0, ids: <String>{}, est: false);
          acc[p.key] = (
            amount: a.amount + p.amount,
            ids: a.ids..add(b.id),
            est: a.est || p.est,
          );
        }
      }
      return acc;
    }

    RevenueRowFigures figures(({double amount, Set<String> ids, bool est})? a) {
      final count = a?.ids.length ?? 0;
      final amount = a?.amount ?? 0;
      return RevenueRowFigures(
        completedAmount: amount,
        completedCount: count,
        averageTicket: count == 0 ? null : (amount / count).roundToDouble(),
      );
    }

    final cur = fold(current);
    final prev = previous == null ? null : fold(previous);
    final both = [...current, ...?previous];
    final rows = [
      for (final key in {...cur.keys, ...?prev?.keys})
        (
          key: key,
          label: _labelOf(axis, key, salon, both),
          current: figures(cur[key]),
          previous: prev == null ? null : figures(prev[key]),
          est: (cur[key]?.est ?? false) || (prev?[key]?.est ?? false),
        ),
    ];
    rows.sort((a, b) {
      final byAmount = b.current.completedAmount.compareTo(
        a.current.completedAmount,
      );
      if (byAmount != 0) return byAmount;
      final byLabel = (a.label.label ?? '').compareTo(b.label.label ?? '');
      if (byLabel != 0) return byLabel;
      return (a.key ?? '').compareTo(b.key ?? '');
    });
    // Basis points by largest remainder: the shares add up to exactly 1.
    final bps = _largestRemainder([
      for (final r in rows) r.current.completedAmount,
    ], total);
    return [
      for (final (i, r) in rows.indexed)
        RevenueRow(
          key: r.key,
          label: r.label.label,
          state: r.label.state,
          share: bps[i] / 10000,
          current: r.current,
          previous: r.previous,
          estimated: r.est,
        ),
    ];
  }

  static List<int> _largestRemainder(List<double> amounts, double total) {
    if (total <= 0) return [for (final _ in amounts) 0];
    final exact = [for (final a in amounts) a / total * 10000];
    final floor = [for (final e in exact) e.floor()];
    var left = 10000 - floor.fold<int>(0, (s, v) => s + v);
    final order = [for (var i = 0; i < exact.length; i++) i]
      ..sort((a, b) => (exact[b] - floor[b]).compareTo(exact[a] - floor[a]));
    for (final i in order) {
      if (left <= 0) break;
      floor[i]++;
      left--;
    }
    return floor;
  }

  /// `day` up to 31 days, `week` up to 92, else `month` (§3.5).
  static RevenueBucket _unitOf(RevenueDayRange r) => r.days <= 31
      ? RevenueBucket.day
      : r.days <= 92
      ? RevenueBucket.week
      : RevenueBucket.month;

  static List<RevenueDayRange> _buckets(RevenueDayRange r) {
    final unit = _unitOf(r);
    final out = <RevenueDayRange>[];
    var start = r.from;
    while (!start.isAfter(r.to)) {
      final natural = switch (unit) {
        RevenueBucket.day => start,
        RevenueBucket.week => addRevenueDays(
          start,
          DateTime.sunday - start.weekday,
        ),
        RevenueBucket.month => revenueDay(start.year, start.month + 1, 0),
      };
      final end = natural.isAfter(r.to) ? r.to : natural;
      out.add(RevenueDayRange(start, end));
      start = addRevenueDays(end, 1);
    }
    return out;
  }

  /// `GET …/analytics/revenue`, folded here. The refusal code when the
  /// query is out of bounds (`invalid_input`, `range_too_long`).
  static ({RevenueAnalytics? data, String? error}) analytics(
    SalonId salon,
    RevenueQuery q,
    DateTime now,
  ) {
    final resolved = _resolve(q, now);
    final p = resolved.period;
    if (p == null) return (data: null, error: resolved.error);
    final all = [
      for (final b in _bookings(salon, now))
        if (_matches(b, q)) b,
    ];
    final current = _inRange(all, p.range);
    final previous = p.comparison == null
        ? null
        : _inRange(all, p.comparison!, cutoff: p.cutoff);
    final currencies =
        <String>{
            for (final b in [...current, ...?previous]) b.currency,
          }.toList()
          ..sort((a, b) => a == 'XOF' ? -1 : (b == 'XOF' ? 1 : a.compareTo(b)));
    final buckets = _buckets(p.range);
    final groups = [
      for (final currency in currencies)
        () {
          final cur = [
            for (final b in current)
              if (b.currency == currency) b,
          ];
          final prev = previous == null
              ? null
              : [
                  for (final b in previous)
                    if (b.currency == currency) b,
                ];
          final figures = _figures(cur, q, p.asOf);
          final total = figures.completedAmount;
          return RevenueGroup(
            currency: currency,
            current: figures,
            previous: prev == null ? null : _figures(prev, q, p.asOf),
            series: [
              for (final bucket in buckets)
                () {
                  final inBucket = [
                    for (final b in cur)
                      if (b.status == 'completed' &&
                          bucket.contains(_day(b.start)))
                        b,
                  ];
                  return RevenueSeriesPoint(
                    start: bucket.from,
                    end: bucket.to,
                    completedAmount: inBucket.fold(
                      0,
                      (s, b) => s + _amountOf(b, q),
                    ),
                    completedCount: inBucket.length,
                  );
                }(),
            ],
            byArtist: q.artistId != null
                ? const []
                : _rows(RevenueAxis.artist, cur, prev, q, salon, total),
            byService: q.serviceId != null
                ? const []
                : _rows(RevenueAxis.service, cur, prev, q, salon, total),
            byChannel: q.channel != null
                ? const []
                : _rows(RevenueAxis.channel, cur, prev, q, salon, total),
          );
        }(),
    ];
    final axis = q.filterAxis;
    final filterKey = switch (axis) {
      RevenueAxis.artist =>
        q.artistId == RevenueQuery.kNoArtist ? null : q.artistId,
      RevenueAxis.service => q.serviceId,
      RevenueAxis.channel => q.channel?.name,
      null => null,
    };
    final filterLabel = axis == null
        ? null
        : _labelOf(axis, filterKey, salon, [...current, ...?previous]);
    return (
      data: RevenueAnalytics(
        period: q.period,
        from: p.range.from,
        to: p.range.to,
        inProgress: p.inProgress,
        timezone: kSalonTz,
        asOf: p.asOf,
        bucket: _unitOf(p.range),
        comparison: RevenueComparison(
          mode: q.compare,
          from: p.comparison?.from,
          to: p.comparison?.to,
          likeForLike: p.cutoff != null,
          cutoff: p.cutoff,
        ),
        filters: RevenueFilters(
          artistId: q.artistId,
          serviceId: q.serviceId,
          channel: q.channel?.name,
          label: filterLabel?.label,
          state: filterLabel?.state,
        ),
        everCompleted: _bookings(
          salon,
          now,
        ).any((b) => b.status == 'completed' && b.start.isBefore(now)),
        groups: groups,
      ),
      error: null,
    );
  }

  /// `GET …/analytics/revenue/appointments`, one page.
  static ({RevenueLedgerPage? data, String? error}) ledger(
    SalonId salon,
    RevenueQuery q,
    RevenueLedgerStatus status,
    int page,
    int pageSize,
    DateTime now,
    DateTime? asOf,
  ) {
    final resolved = _resolve(q, now);
    final p = resolved.period;
    if (p == null) return (data: null, error: resolved.error);
    final at = (asOf ?? now).toUtc();
    final rows = [
      for (final b in _inRange([
        for (final b in _bookings(salon, now))
          if (_matches(b, q)) b,
      ], p.range))
        if (switch (status) {
          RevenueLedgerStatus.completed => b.status == 'completed',
          RevenueLedgerStatus.upcoming =>
            b.status == 'confirmed' && !b.end.isBefore(at),
          RevenueLedgerStatus.toClose =>
            b.status == 'confirmed' && b.end.isBefore(at),
          RevenueLedgerStatus.noShow => b.status == 'noShow',
          RevenueLedgerStatus.cancelled => b.status == 'cancelled',
        })
          b,
    ];
    rows.sort((a, b) {
      final byDate = status == RevenueLedgerStatus.upcoming
          ? a.start.compareTo(b.start)
          : b.start.compareTo(a.start);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    final live = _liveArtists(salon);
    final liveServices = _liveServices(salon);
    final slice = rows.skip((page - 1) * pageSize).take(pageSize);
    return (
      data: RevenueLedgerPage(
        items: [
          for (final b in slice)
            RevenueLedgerRow(
              appointmentId: b.id,
              appointmentDate: b.start,
              status: b.status,
              amount: _amountOf(b, q),
              totalPrice: b.total,
              currency: b.currency,
              clientDisplayName: b.client,
              serviceNames: [
                for (final (i, id) in b.serviceIds.indexed)
                  liveServices[id] ?? b.serviceNamesKept?[i],
              ],
              artistLabel: b.artistId == null
                  ? null
                  : live[b.artistId] ?? b.artistNameKept,
              artistState: b.artistId == null
                  ? RevenueRowState.unassigned
                  : live.containsKey(b.artistId)
                  ? RevenueRowState.active
                  : RevenueRowState.removed,
              channel: b.channel,
              estimated: q.serviceId != null && b.estimated,
            ),
        ],
        page: page,
        pageSize: pageSize,
        total: rows.length,
        asOf: at,
      ),
      error: null,
    );
  }
}

class RevenueDayRange {
  const RevenueDayRange(this.from, this.to);
  final DateTime from;
  final DateTime to;
  int get days => revenueDaysBetween(from, to) + 1;
  bool contains(DateTime d) => !d.isBefore(from) && !d.isAfter(to);
}

class _Period {
  const _Period({
    required this.range,
    required this.comparison,
    required this.inProgress,
    required this.cutoff,
    required this.asOf,
  });
  final RevenueDayRange range;
  final RevenueDayRange? comparison;
  final bool inProgress;
  final DateTime? cutoff;
  final DateTime asOf;
}

class _Booking {
  const _Booking({
    required this.id,
    required this.start,
    required this.minutes,
    required this.status,
    required this.artistId,
    required this.artistNameKept,
    required this.serviceIds,
    required this.lines,
    required this.serviceNamesKept,
    required this.estimated,
    required this.currency,
    required this.channel,
    required this.client,
  });

  final String id;
  final DateTime start;
  final int minutes;
  final String status;
  final String? artistId;
  final String? artistNameKept;
  final List<String> serviceIds;
  final List<double> lines;
  final List<String?>? serviceNamesKept;
  final bool estimated;
  final String currency;
  final RevenueChannel channel;
  final String client;

  DateTime get end => start.add(Duration(minutes: minutes));
  double get total => lines.fold(0, (s, v) => s + v);
}

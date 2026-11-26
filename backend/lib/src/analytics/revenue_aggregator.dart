import 'revenue_period.dart';

// The fold of the revenue analytics — every figure, row and label of
// docs/design/pro-revenue-analytics.md §3.2–§3.4, in one place. Pure: rows in,
// the response's JSON out. The in-memory twin and Postgres feed it the same
// narrow rows (`AppointmentRepository.revenueRows`), so there is one
// definition of each figure, unit-testable without a database (§9.1).

/// The three channels a booking records since R1 (`appointments.channel`).
const Set<String> kRecordedChannels = {'app', 'web', 'salon'};

/// Every channel a row can be filed under: the recorded three, and `online`
/// — an online booking made before the channel was recorded.
const Set<String> kRevenueChannels = {'app', 'web', 'salon', 'online'};

/// ISO-4217 codes with no minor unit, among the markets MyWeli serves or will
/// (multi-pays). Any other currency rounds to two decimals.
const Set<String> kZeroDecimalCurrencies = {
  'XOF',
  'XAF',
  'GNF',
  'KMF',
  'RWF',
  'BIF',
  'DJF',
  'UGX',
  'JPY',
  'KRW',
  'VND',
  'CLP',
  'PYG',
  'ISK',
  'VUV',
  'XPF',
};

/// [amount] rounded to [currency]'s unit (§3.4 step 3).
double roundToCurrency(double amount, String currency) {
  if (kZeroDecimalCurrencies.contains(currency)) {
    return amount.roundToDouble();
  }
  return (amount * 100).roundToDouble() / 100;
}

/// The channel a booking is filed under (§3.3, §8.1): its recorded channel,
/// else `salon` for a booking the salon entered (`userId = 'manual'`), else
/// `online` (made before R1, app or website unknown).
String revenueChannelOf(Map<String, dynamic> row) {
  final recorded = row['channel'];
  if (recorded is String && kRecordedChannels.contains(recorded)) {
    return recorded;
  }
  return row['userId'] == 'manual' ? 'salon' : 'online';
}

/// The collaborateur a booking is filed under: its `artistId`, or null when
/// it has none — an empty string included (§2.1, §3.3).
String? revenueArtistKeyOf(Map<String, dynamic> row) {
  final id = row['artistId'];
  return (id is String && id.isNotEmpty) ? id : null;
}

/// What the aggregator reads of the salon itself: its live roster and
/// catalogue, for the labels and for the estimate of older bookings.
class RevenueCatalogue {
  const RevenueCatalogue({
    this.artistNames = const {},
    this.serviceNames = const {},
    this.servicePrices = const {},
  });

  /// From a salon document (`artists`, `services`).
  factory RevenueCatalogue.fromSalon(Map<String, dynamic>? salon) {
    final artists = <String, String?>{};
    for (final a in (salon?['artists'] as List?) ?? const []) {
      if (a is Map && a['id'] is String) {
        artists[a['id'] as String] = a['name'] as String?;
      }
    }
    final names = <String, String?>{};
    final prices = <String, double>{};
    for (final s in (salon?['services'] as List?) ?? const []) {
      if (s is Map && s['id'] is String) {
        final id = s['id'] as String;
        names[id] = s['name'] as String?;
        final price = s['price'];
        prices[id] = price is num ? price.toDouble() : 0;
      }
    }
    return RevenueCatalogue(
      artistNames: artists,
      serviceNames: names,
      servicePrices: prices,
    );
  }

  /// The roster: id → name.
  final Map<String, String?> artistNames;

  /// The catalogue: id → name.
  final Map<String, String?> serviceNames;

  /// The catalogue: id → today's price.
  final Map<String, double> servicePrices;
}

/// One prestation line of a booking: as kept at booking time (R1), or
/// estimated at read time for a booking made before (§3.4).
class RevenueLine {
  const RevenueLine({
    required this.serviceId,
    required this.keptName,
    required this.amount,
    required this.estimated,
  });

  final String serviceId;

  /// The name the line was sold as (R1); null for an estimated line.
  final String? keptName;
  final double amount;
  final bool estimated;
}

/// The booking's `serviceIds`, whatever form a read handed them in.
List<String> _serviceIdsOf(Map<String, dynamic> row) {
  final ids = row['serviceIds'];
  if (ids is! List) return const [];
  return [
    for (final id in ids)
      if (id is String) id,
  ];
}

/// The prestation lines of a booking (§3.4).
///
/// Kept lines (R1) are returned as they are. Otherwise they are estimated —
/// the one algorithm, here only:
/// 1. today's catalogue price of each `serviceId` (0 for a service gone);
/// 2. the booking's `totalPrice` shared in proportion to them, equally when
///    they are all 0;
/// 3. each share rounded to the currency's unit, the remainder given to the
///    largest line (the first of equals), so the lines add up to `totalPrice`
///    exactly;
/// 4. each marked `estimated` — except the line of a single-service booking,
///    which is its `totalPrice` and exact by construction.
List<RevenueLine> revenueLinesOf(
  Map<String, dynamic> row,
  RevenueCatalogue catalogue,
) {
  final kept = row['serviceLines'];
  if (kept is List && kept.isNotEmpty) {
    final lines = <RevenueLine>[];
    var readable = true;
    for (final l in kept) {
      if (l is! Map || l['serviceId'] is! String || l['price'] is! num) {
        readable = false;
        break;
      }
      lines.add(
        RevenueLine(
          serviceId: l['serviceId'] as String,
          keptName: l['name'] as String?,
          amount: (l['price'] as num).toDouble(),
          estimated: false,
        ),
      );
    }
    if (readable) return lines;
  }

  final ids = _serviceIdsOf(row);
  if (ids.isEmpty) return const [];
  final total = (row['totalPrice'] as num?)?.toDouble() ?? 0;
  if (ids.length == 1) {
    return [
      RevenueLine(
        serviceId: ids.single,
        keptName: null,
        amount: total,
        estimated: false,
      ),
    ];
  }
  final currency = (row['currency'] as String?) ?? 'XOF';
  final weights = [for (final id in ids) catalogue.servicePrices[id] ?? 0.0];
  final sum = weights.fold<double>(0, (a, b) => a + (b > 0 ? b : 0));
  final shares = [
    for (final w in weights)
      roundToCurrency(
        sum > 0 ? total * (w > 0 ? w : 0) / sum : total / ids.length,
        currency,
      ),
  ];
  final remainder = roundToCurrency(
    total - shares.fold<double>(0, (a, b) => a + b),
    currency,
  );
  if (remainder != 0) {
    var largest = 0;
    for (var i = 1; i < shares.length; i++) {
      if (shares[i] > shares[largest]) largest = i;
    }
    shares[largest] = roundToCurrency(shares[largest] + remainder, currency);
  }
  return [
    for (var i = 0; i < ids.length; i++)
      RevenueLine(
        serviceId: ids[i],
        keptName: null,
        amount: shares[i],
        estimated: true,
      ),
  ];
}

/// The filters of a request (§7.1). `artistId == 'none'` is « no
/// collaborateur ».
class RevenueFilters {
  const RevenueFilters({this.artistId, this.serviceId, this.channel});

  static const none = 'none';

  final String? artistId;
  final String? serviceId;
  final String? channel;
}

/// One booking as the fold sees it, in the context of the filters.
class _Entry {
  _Entry({
    required this.row,
    required this.status,
    required this.start,
    required this.end,
    required this.currency,
    required this.artistKey,
    required this.channel,
    required this.lines,
    required this.amount,
    required this.amountEstimated,
  });

  final Map<String, dynamic> row;
  final String? status;
  final DateTime start;
  final DateTime end;
  final String currency;
  final String? artistKey;
  final String channel;
  final List<RevenueLine> lines;

  /// What this booking contributes to the figures: its `totalPrice`, or —
  /// under a prestation filter — that prestation's lines.
  final double amount;
  final bool amountEstimated;
}

/// The fold (§3.2–§3.4) over the current range's rows and, with a comparison,
/// the comparison's rows (already cut by the repository read). Returns the
/// `RevenueAnalytics` JSON of docs/api/openapi.yaml.
Map<String, dynamic> aggregateRevenue({
  required ResolvedRevenuePeriod period,
  required List<Map<String, dynamic>> currentRows,
  required List<Map<String, dynamic>>? previousRows,
  required RevenueCatalogue catalogue,
  required RevenueFilters filters,
  required String salonCurrency,
  required bool everCompleted,
}) {
  final current = _entries(currentRows, catalogue, filters);
  final previous = previousRows == null
      ? null
      : _entries(previousRows, catalogue, filters);

  final currencies =
      {
        for (final e in current) e.currency,
        for (final e in previous ?? const <_Entry>[]) e.currency,
      }.toList()..sort((a, b) {
        if (a == b) return 0;
        if (a == salonCurrency) return -1;
        if (b == salonCurrency) return 1;
        return a.compareTo(b);
      });

  // The latest name kept for each collaborateur and prestation, across both
  // ranges: the label of one that has left the roster or the catalogue.
  final keptArtist = <String, ({DateTime at, String name})>{};
  final keptService = <String, ({DateTime at, String name})>{};
  for (final e in [...current, ...?previous]) {
    final key = e.artistKey;
    final name = e.row['artistNameKept'];
    if (key != null && name is String && name.isNotEmpty) {
      final seen = keptArtist[key];
      if (seen == null || e.start.isAfter(seen.at)) {
        keptArtist[key] = (at: e.start, name: name);
      }
    }
    for (final l in e.lines) {
      final n = l.keptName;
      if (n == null || n.isEmpty) continue;
      final seen = keptService[l.serviceId];
      if (seen == null || e.start.isAfter(seen.at)) {
        keptService[l.serviceId] = (at: e.start, name: n);
      }
    }
  }

  ({String? label, String state}) artistLabel(String? key) {
    if (key == null) return (label: null, state: 'unassigned');
    if (catalogue.artistNames.containsKey(key)) {
      return (label: catalogue.artistNames[key], state: 'active');
    }
    return (label: keptArtist[key]?.name, state: 'removed');
  }

  ({String? label, String state}) serviceLabel(String key) {
    if (catalogue.serviceNames.containsKey(key)) {
      return (label: catalogue.serviceNames[key], state: 'active');
    }
    return (label: keptService[key]?.name, state: 'removed');
  }

  ({String? label, String state}) channelLabel(String key) =>
      (label: null, state: key == 'online' ? 'legacy' : 'active');

  final groups = <Map<String, dynamic>>[];
  for (final currency in currencies) {
    final cur = [
      for (final e in current)
        if (e.currency == currency) e,
    ];
    final prev = previous == null
        ? null
        : [
            for (final e in previous)
              if (e.currency == currency) e,
          ];
    final curFigures = _figures(cur, period.asOf, currency);
    final groupTotal = curFigures['completedAmount'] as double;

    groups.add({
      'currency': currency,
      'current': curFigures,
      'previous': prev == null ? null : _figures(prev, period.asOf, currency),
      'series': _series(cur, period, currency),
      'byArtist': filters.artistId != null
          ? const <Map<String, dynamic>>[]
          : _rows(
              cur,
              prev,
              (e) => [
                (key: e.artistKey, amount: e.amount, est: e.amountEstimated),
              ],
              artistLabel,
              groupTotal,
              currency,
            ),
      'byService': filters.serviceId != null
          ? const <Map<String, dynamic>>[]
          : _rows(
              cur,
              prev,
              (e) => [
                for (final l in e.lines)
                  (key: l.serviceId, amount: l.amount, est: l.estimated),
              ],
              (key) => serviceLabel(key!),
              groupTotal,
              currency,
            ),
      'byChannel': filters.channel != null
          ? const <Map<String, dynamic>>[]
          : _rows(
              cur,
              prev,
              (e) => [
                (key: e.channel, amount: e.amount, est: e.amountEstimated),
              ],
              (key) => channelLabel(key!),
              groupTotal,
              currency,
            ),
    });
  }

  ({String? label, String? state}) filterLabel() {
    if (filters.artistId != null) {
      return filters.artistId == RevenueFilters.none
          ? artistLabel(null)
          : artistLabel(filters.artistId);
    }
    if (filters.serviceId != null) return serviceLabel(filters.serviceId!);
    if (filters.channel != null) return channelLabel(filters.channel!);
    return (label: null, state: null);
  }

  final filterRow = filterLabel();
  final comparison = period.comparison;
  return {
    'period': period.kind.name,
    'from': revenueDateKey(period.range.from),
    'to': revenueDateKey(period.range.to),
    'inProgress': period.inProgress,
    'timezone': period.timezone,
    'asOf': period.asOf.toIso8601String(),
    'bucket': period.bucketUnit.name,
    'comparison': {
      'mode': period.compareMode.name,
      'from': comparison == null ? null : revenueDateKey(comparison.from),
      'to': comparison == null ? null : revenueDateKey(comparison.to),
      'likeForLike': period.likeForLike,
      'cutoff': period.cutoffUtc?.toIso8601String(),
    },
    'filters': {
      'artistId': filters.artistId,
      'serviceId': filters.serviceId,
      'channel': filters.channel,
      'label': filterRow.label,
      'state': filterRow.state,
    },
    'everCompleted': everCompleted,
    'groups': groups,
  };
}

List<_Entry> _entries(
  List<Map<String, dynamic>> rows,
  RevenueCatalogue catalogue,
  RevenueFilters filters,
) {
  final out = <_Entry>[];
  for (final row in rows) {
    final artistKey = revenueArtistKeyOf(row);
    if (filters.artistId != null) {
      final wanted = filters.artistId == RevenueFilters.none
          ? null
          : filters.artistId;
      if (artistKey != wanted) continue;
    }
    final channel = revenueChannelOf(row);
    if (filters.channel != null && channel != filters.channel) continue;
    final lines = revenueLinesOf(row, catalogue);
    double amount;
    var estimated = false;
    if (filters.serviceId == null) {
      amount = (row['totalPrice'] as num?)?.toDouble() ?? 0;
    } else {
      amount = 0;
      var matched = false;
      for (final l in lines) {
        if (l.serviceId != filters.serviceId) continue;
        matched = true;
        amount += l.amount;
        estimated = estimated || l.estimated;
      }
      if (!matched) continue;
    }
    final start = DateTime.parse(row['appointmentDate'] as String).toUtc();
    final minutes = (row['durationMinutes'] as num?)?.toInt() ?? 0;
    out.add(
      _Entry(
        row: row,
        status: row['status'] as String?,
        start: start,
        end: start.add(Duration(minutes: minutes)),
        currency: (row['currency'] as String?) ?? 'XOF',
        artistKey: artistKey,
        channel: channel,
        lines: lines,
        amount: amount,
        amountEstimated: estimated,
      ),
    );
  }
  return out;
}

double? _average(double amount, int count, String currency) =>
    count == 0 ? null : roundToCurrency(amount / count, currency);

/// §3.2, for one set of bookings in one currency, against [asOf].
Map<String, dynamic> _figures(
  List<_Entry> entries,
  DateTime asOf,
  String currency,
) {
  var completedAmount = 0.0;
  var completedCount = 0;
  var upcomingAmount = 0.0;
  var upcomingCount = 0;
  var pendingAmount = 0.0;
  var pendingCount = 0;
  var toCloseAmount = 0.0;
  var toCloseCount = 0;
  var noShowAmount = 0.0;
  var noShowCount = 0;
  var cancelledAmount = 0.0;
  var cancelledCount = 0;
  var estimated = false;
  for (final e in entries) {
    switch (e.status) {
      case 'completed':
        completedAmount += e.amount;
        completedCount++;
        estimated = estimated || e.amountEstimated;
      case 'confirmed':
        // By the END, not the start: a three-hour braid that began ten
        // minutes ago is still « Prévu ».
        if (e.end.isBefore(asOf)) {
          toCloseAmount += e.amount;
          toCloseCount++;
        } else {
          upcomingAmount += e.amount;
          upcomingCount++;
        }
      case 'pending':
        // A request nobody answered before it began counts nowhere.
        if (!e.start.isBefore(asOf)) {
          pendingAmount += e.amount;
          pendingCount++;
        }
      case 'noShow':
        noShowAmount += e.amount;
        noShowCount++;
      case 'cancelled':
        cancelledAmount += e.amount;
        cancelledCount++;
    }
  }
  final attended = completedCount + noShowCount;
  return {
    'completedAmount': roundToCurrency(completedAmount, currency),
    'completedCount': completedCount,
    'averageTicket': _average(completedAmount, completedCount, currency),
    'upcomingAmount': roundToCurrency(upcomingAmount, currency),
    'upcomingCount': upcomingCount,
    'pendingAmount': roundToCurrency(pendingAmount, currency),
    'pendingCount': pendingCount,
    'toCloseAmount': roundToCurrency(toCloseAmount, currency),
    'toCloseCount': toCloseCount,
    'noShowAmount': roundToCurrency(noShowAmount, currency),
    'noShowCount': noShowCount,
    'noShowRate': attended == 0 ? null : noShowCount / attended,
    'cancelledAmount': roundToCurrency(cancelledAmount, currency),
    'cancelledCount': cancelledCount,
    'estimated': estimated,
  };
}

/// The chart: completed bookings per bucket of the current range, by their
/// salon calendar day; every bucket present, zero-filled.
List<Map<String, dynamic>> _series(
  List<_Entry> entries,
  ResolvedRevenuePeriod period,
  String currency,
) {
  final amounts = List<double>.filled(period.buckets.length, 0);
  final counts = List<int>.filled(period.buckets.length, 0);
  for (final e in entries) {
    if (e.status != 'completed') continue;
    final i = period.bucketIndexOf(salonDateOf(e.start, period.timezone));
    if (i < 0) continue;
    amounts[i] += e.amount;
    counts[i]++;
  }
  return [
    for (var i = 0; i < period.buckets.length; i++)
      {
        'start': revenueDateKey(period.buckets[i].from),
        'end': revenueDateKey(period.buckets[i].to),
        'completedAmount': roundToCurrency(amounts[i], currency),
        'completedCount': counts[i],
      },
  ];
}

typedef _Part = ({String? key, double amount, bool est});

class _Acc {
  double amount = 0;
  final Set<Object> bookings = {};
  bool estimated = false;
}

/// One axis's rows: the completed bookings of each range split by [partsOf]
/// (one part per booking, or one per prestation line). A booking with two
/// lines of the same prestation counts once in that row.
List<Map<String, dynamic>> _rows(
  List<_Entry> current,
  List<_Entry>? previous,
  List<_Part> Function(_Entry) partsOf,
  ({String? label, String state}) Function(String? key) labelOf,
  double groupTotal,
  String currency,
) {
  Map<String?, _Acc> fold(List<_Entry> entries) {
    final acc = <String?, _Acc>{};
    for (final e in entries) {
      if (e.status != 'completed') continue;
      for (final p in partsOf(e)) {
        final a = acc.putIfAbsent(p.key, _Acc.new);
        a.amount += p.amount;
        a.bookings.add(e);
        a.estimated = a.estimated || p.est;
      }
    }
    return acc;
  }

  final cur = fold(current);
  final prev = previous == null ? null : fold(previous);
  final keys = {...cur.keys, ...?prev?.keys};

  Map<String, dynamic> figures(_Acc? a) {
    final amount = roundToCurrency(a?.amount ?? 0, currency);
    final count = a?.bookings.length ?? 0;
    return {
      'completedAmount': amount,
      'completedCount': count,
      'averageTicket': _average(a?.amount ?? 0, count, currency),
    };
  }

  final rows = <Map<String, dynamic>>[];
  for (final key in keys) {
    final l = labelOf(key);
    rows.add({
      'key': key,
      'label': l.label,
      'state': l.state,
      'share': 0.0,
      'current': figures(cur[key]),
      'previous': prev == null ? null : figures(prev[key]),
      'estimated':
          (cur[key]?.estimated ?? false) || (prev?[key]?.estimated ?? false),
    });
  }

  // A total order, so two reads never swap rows: amount, then label, then
  // key — never the map's order.
  rows.sort((a, b) {
    final byAmount = ((b['current'] as Map)['completedAmount'] as double)
        .compareTo((a['current'] as Map)['completedAmount'] as double);
    if (byAmount != 0) return byAmount;
    final byLabel = ((a['label'] as String?) ?? '').compareTo(
      (b['label'] as String?) ?? '',
    );
    if (byLabel != 0) return byLabel;
    return ((a['key'] as String?) ?? '').compareTo((b['key'] as String?) ?? '');
  });

  _shares(rows, groupTotal);
  return rows;
}

/// Each row's share of [total], in basis points by largest remainder, so the
/// shares of one axis add up to exactly 10 000 / 10 000 when [total] > 0.
void _shares(List<Map<String, dynamic>> rows, double total) {
  if (total <= 0 || rows.isEmpty) return;
  const units = 10000;
  final raw = [
    for (final r in rows)
      ((r['current'] as Map)['completedAmount'] as double) / total * units,
  ];
  final floors = [for (final x in raw) x.floor()];
  var left = units - floors.fold<int>(0, (a, b) => a + b);
  final order = List<int>.generate(rows.length, (i) => i)
    ..sort((a, b) {
      final byFraction = (raw[b] - floors[b]).compareTo(raw[a] - floors[a]);
      return byFraction != 0 ? byFraction : a.compareTo(b);
    });
  for (final i in order) {
    if (left <= 0) break;
    if (raw[i] <= 0) continue;
    floors[i]++;
    left--;
  }
  for (var i = 0; i < rows.length; i++) {
    rows[i]['share'] = floors[i] / units;
  }
}

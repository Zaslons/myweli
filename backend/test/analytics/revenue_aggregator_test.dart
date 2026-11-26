import 'package:myweli_backend/src/analytics/revenue_aggregator.dart';
import 'package:myweli_backend/src/analytics/revenue_period.dart';
import 'package:test/test.dart';

/// The fold — docs/design/pro-revenue-analytics.md §3.2–§3.4, §13.1
/// (« Aggregator »). Narrow rows in, the `RevenueAnalytics` JSON out.
void main() {
  // Wednesday 25 November 2026, 14:30 in Abidjan (UTC+0).
  final asOf = DateTime.utc(2026, 11, 25, 14, 30);

  ResolvedRevenuePeriod period({
    RevenuePeriodKind kind = RevenuePeriodKind.month,
    RevenueCompareMode compare = RevenueCompareMode.previous,
    String tz = 'Africa/Abidjan',
    DateTime? at,
  }) => resolveRevenuePeriod(
    kind: kind,
    compare: compare,
    asOf: at ?? asOf,
    tzName: tz,
  ).period!;

  var n = 0;
  Map<String, dynamic> row({
    String status = 'completed',
    DateTime? at,
    int minutes = 60,
    num price = 10000,
    String currency = 'XOF',
    String? artistId,
    String? artistNameKept,
    String userId = 'u1',
    String? channel = 'app',
    List<String> serviceIds = const ['s1'],
    List<Map<String, dynamic>>? lines,
    String? id,
  }) => {
    'id': id ?? 'a${(n++).toString().padLeft(3, '0')}',
    'status': status,
    'appointmentDate': (at ?? DateTime.utc(2026, 11, 10, 10)).toIso8601String(),
    'durationMinutes': minutes,
    'artistId': artistId,
    'artistNameKept': artistNameKept,
    'totalPrice': price.toDouble(),
    'currency': currency,
    'userId': userId,
    'channel': channel,
    'serviceIds': serviceIds,
    'serviceLines':
        lines ??
        [
          for (final s in serviceIds)
            {
              'serviceId': s,
              'name': 'kept $s',
              'price': price / serviceIds.length,
              'durationMinutes': 30,
            },
        ],
  };

  const catalogue = RevenueCatalogue(
    artistNames: {'ar1': 'Aminata', 'ar2': 'Bintou'},
    serviceNames: {'s1': 'Tresses', 's2': 'Manucure', 's3': 'Brushing'},
    servicePrices: {'s1': 20000, 's2': 5000, 's3': 15000},
  );

  Map<String, dynamic> fold(
    List<Map<String, dynamic>> current, {
    List<Map<String, dynamic>>? previous = const [],
    ResolvedRevenuePeriod? p,
    RevenueFilters filters = const RevenueFilters(),
    RevenueCatalogue cat = catalogue,
    String salonCurrency = 'XOF',
  }) => aggregateRevenue(
    period: p ?? period(),
    currentRows: current,
    previousRows: previous,
    catalogue: cat,
    filters: filters,
    salonCurrency: salonCurrency,
    everCompleted: true,
  );

  Map<String, dynamic> group0(Map<String, dynamic> r) =>
      (r['groups'] as List).first as Map<String, dynamic>;
  Map<String, dynamic> figures(Map<String, dynamic> r) =>
      group0(r)['current'] as Map<String, dynamic>;

  group('§3.2 — each figure, by status and by « now »', () {
    test('completed → Réalisé; average ticket', () {
      final f = figures(
        fold([
          row(price: 10000),
          row(price: 20000),
          row(status: 'cancelled', price: 7000),
        ]),
      );
      expect(f['completedAmount'], 30000);
      expect(f['completedCount'], 2);
      expect(f['averageTicket'], 15000);
      expect(f['cancelledAmount'], 7000);
      expect(f['cancelledCount'], 1);
    });

    test('« À clôturer » by the END: a 3-hour braid begun 10 minutes ago is '
        'still « Prévu »; one that ended a minute ago is « À clôturer »', () {
      final f = figures(
        fold([
          row(
            status: 'confirmed',
            at: asOf.subtract(const Duration(minutes: 10)),
            minutes: 180,
            price: 30000,
          ),
          row(
            status: 'confirmed',
            at: asOf.subtract(const Duration(minutes: 61)),
            price: 8000,
          ),
        ]),
      );
      expect(f['upcomingAmount'], 30000);
      expect(f['upcomingCount'], 1);
      expect(f['toCloseAmount'], 8000);
      expect(f['toCloseCount'], 1);
    });

    test('a booking that ends exactly now is still « Prévu »', () {
      final f = figures(
        fold([
          row(
            status: 'confirmed',
            at: asOf.subtract(const Duration(minutes: 60)),
          ),
        ]),
      );
      expect(f['upcomingCount'], 1);
      expect(f['toCloseCount'], 0);
    });

    test('a completed booking dated later this month counts in Réalisé', () {
      final f = figures(
        fold([row(at: DateTime.utc(2026, 11, 28, 10), price: 12000)]),
      );
      expect(f['completedAmount'], 12000);
    });

    test('pending: from now on counts; a past request counts nowhere', () {
      final f = figures(
        fold([
          row(status: 'pending', at: asOf.add(const Duration(hours: 2))),
          row(status: 'pending', at: asOf.subtract(const Duration(hours: 2))),
        ]),
      );
      expect(f['pendingCount'], 1);
      expect(f['pendingAmount'], 10000);
      expect(f['upcomingCount'], 0);
      expect(f['toCloseCount'], 0);
      expect(f['completedCount'], 0);
    });

    test('absences and their rate; null rate and ticket with nothing', () {
      final f = figures(
        fold([row(), row(), row(), row(status: 'noShow', price: 4000)]),
      );
      expect(f['noShowCount'], 1);
      expect(f['noShowAmount'], 4000);
      expect(f['noShowRate'], 0.25);

      final empty = figures(fold([row(status: 'cancelled')]));
      expect(empty['noShowRate'], isNull);
      expect(empty['averageTicket'], isNull);
    });
  });

  group('currencies are grouped, never summed', () {
    test('two currencies → two groups, the salon\'s own first', () {
      final r = fold([
        row(currency: 'EUR', price: 50),
        row(price: 10000),
        row(currency: 'XAF', price: 3000),
      ]);
      final groups = r['groups'] as List;
      expect(
        [for (final g in groups) (g as Map)['currency']],
        ['XOF', 'EUR', 'XAF'],
      );
      expect(((groups[0] as Map)['current'] as Map)['completedAmount'], 10000);
      expect(((groups[1] as Map)['current'] as Map)['completedAmount'], 50);
    });

    test('a currency met only in the comparison still has a group', () {
      final r = fold(
        [row()],
        previous: [row(currency: 'EUR', at: DateTime.utc(2026, 10, 3))],
      );
      expect((r['groups'] as List), hasLength(2));
    });

    test('nothing in either range → no group', () {
      expect(fold(const [])['groups'], isEmpty);
    });
  });

  group('§3.3 — the breakdowns', () {
    test('par collaborateur: null and empty both « unassigned », one row', () {
      final r = fold([
        row(artistId: null, price: 1000),
        row(artistId: '', price: 2000),
        row(artistId: 'ar1', price: 4000),
      ]);
      final rows = group0(r)['byArtist'] as List;
      expect(rows, hasLength(2));
      final unassigned =
          rows.firstWhere((x) => (x as Map)['key'] == null) as Map;
      expect(unassigned['state'], 'unassigned');
      expect(unassigned['label'], isNull);
      expect((unassigned['current'] as Map)['completedAmount'], 3000);
      expect((unassigned['current'] as Map)['completedCount'], 2);
    });

    test('the labels table, row by row', () {
      final r = fold([
        row(artistId: 'ar1', artistNameKept: 'Old name', price: 9000),
        row(artistId: 'gone', artistNameKept: 'Kadi', price: 8000),
        row(artistId: 'ghost', price: 7000), // no kept name
        row(
          serviceIds: ['s9'],
          lines: [
            {'serviceId': 's9', 'name': 'Défrisage', 'price': 6000},
          ],
          price: 6000,
          channel: 'web',
        ),
        row(
          serviceIds: ['s8'],
          lines: null,
          price: 5000,
          channel: null,
          userId: 'manual',
        ).also((m) => m['serviceLines'] = null),
        row(channel: null, userId: 'u2', price: 1000),
      ]);
      final g = group0(r);
      Map<dynamic, dynamic> byKey(String axis, String? key) =>
          (g[axis] as List).firstWhere((x) => (x as Map)['key'] == key)
              as Map<dynamic, dynamic>;

      // Live name wins over the kept one.
      expect(byKey('byArtist', 'ar1')['label'], 'Aminata');
      expect(byKey('byArtist', 'ar1')['state'], 'active');
      expect(byKey('byArtist', 'gone')['label'], 'Kadi');
      expect(byKey('byArtist', 'gone')['state'], 'removed');
      expect(byKey('byArtist', 'ghost')['label'], isNull);
      expect(byKey('byArtist', 'ghost')['state'], 'removed');

      expect(byKey('byService', 's1')['label'], 'Tresses');
      expect(byKey('byService', 's1')['state'], 'active');
      expect(byKey('byService', 's9')['label'], 'Défrisage');
      expect(byKey('byService', 's9')['state'], 'removed');
      expect(byKey('byService', 's8')['label'], isNull);
      expect(byKey('byService', 's8')['state'], 'removed');

      expect(byKey('byChannel', 'app')['state'], 'active');
      expect(byKey('byChannel', 'web')['state'], 'active');
      expect(byKey('byChannel', 'salon')['state'], 'active');
      expect(byKey('byChannel', 'online')['state'], 'legacy');
      for (final c in g['byChannel'] as List) {
        expect((c as Map)['label'], isNull, reason: 'the client names it');
      }
    });

    test('the removed collaborateur reads the LATEST kept name', () {
      final r = fold([
        row(
          artistId: 'gone',
          artistNameKept: 'Kadi',
          at: DateTime.utc(2026, 11, 2),
        ),
        row(
          artistId: 'gone',
          artistNameKept: 'Kadidja',
          at: DateTime.utc(2026, 11, 20),
        ),
      ]);
      expect(
        ((group0(r)['byArtist'] as List).single as Map)['label'],
        'Kadidja',
      );
    });

    test(
      'a renamed service shows its new name over all its history — one row',
      () {
        final r = fold([
          row(
            lines: [
              {
                'serviceId': 's1',
                'name': 'Tresses (ancien nom)',
                'price': 10000,
              },
            ],
          ),
          row(),
        ]);
        final rows = group0(r)['byService'] as List;
        expect(rows, hasLength(1));
        expect((rows.single as Map)['label'], 'Tresses');
      },
    );

    test('channel: recorded, else salon for a manual booking, else online', () {
      expect(revenueChannelOf({'channel': 'web', 'userId': 'u'}), 'web');
      expect(revenueChannelOf({'channel': null, 'userId': 'manual'}), 'salon');
      expect(revenueChannelOf({'channel': null, 'userId': 'u'}), 'online');
      expect(
        revenueChannelOf({'channel': 'nonsense', 'userId': 'u'}),
        'online',
      );
    });

    test('a booking with two prestations counts once in each row; the '
        'amounts add up exactly', () {
      final r = fold([
        row(
          serviceIds: ['s1', 's2'],
          price: 25000,
          lines: [
            {'serviceId': 's1', 'name': 'x', 'price': 20000},
            {'serviceId': 's2', 'name': 'y', 'price': 5000},
          ],
        ),
      ]);
      final rows = group0(r)['byService'] as List;
      expect(rows, hasLength(2));
      for (final x in rows) {
        expect(((x as Map)['current'] as Map)['completedCount'], 1);
      }
      final sum = rows.fold<double>(
        0,
        (a, x) =>
            a + (((x as Map)['current'] as Map)['completedAmount'] as num),
      );
      expect(sum, 25000);
    });

    test('a duplicate in service_ids: one row, the booking counted once', () {
      final r = fold([
        row(
          serviceIds: ['s1', 's1'],
          price: 40000,
          lines: [
            {'serviceId': 's1', 'name': 'x', 'price': 20000},
            {'serviceId': 's1', 'name': 'x', 'price': 20000},
          ],
        ),
      ]);
      final rows = group0(r)['byService'] as List;
      expect(rows, hasLength(1));
      final cur = (rows.single as Map)['current'] as Map;
      expect(cur['completedAmount'], 40000);
      expect(cur['completedCount'], 1);
    });

    test('only completed bookings make rows; a row appears when it sold in '
        'either range', () {
      final r = fold(
        [row(artistId: 'ar1'), row(artistId: 'ar2', status: 'confirmed')],
        previous: [row(artistId: 'ar2', at: DateTime.utc(2026, 10, 5))],
      );
      final rows = group0(r)['byArtist'] as List;
      expect([for (final x in rows) (x as Map)['key']], ['ar1', 'ar2']);
      final ar2 = rows.last as Map;
      expect((ar2['current'] as Map)['completedAmount'], 0);
      expect((ar2['current'] as Map)['averageTicket'], isNull);
      expect((ar2['previous'] as Map)['completedAmount'], 10000);
      expect(ar2['share'], 0);
    });

    test('the sort is a total order: amount, then label, then key — never '
        'the order rows arrived in', () {
      List<Object?> keys(List<Map<String, dynamic>> rows) => [
        for (final x in group0(fold(rows))['byArtist'] as List)
          (x as Map)['key'],
      ];
      final rows = [
        row(artistId: 'zz', price: 5000),
        row(artistId: 'ar2', price: 5000),
        row(artistId: 'ar1', price: 5000),
        row(artistId: 'aa', price: 9000),
      ];
      final forward = keys(rows);
      final backward = keys(rows.reversed.toList());
      // aa (9000, removed, no label → ''), then the 5000s by label:
      // '' (zz) < 'Aminata' (ar1) < 'Bintou' (ar2).
      expect(forward, ['aa', 'zz', 'ar1', 'ar2']);
      expect(backward, forward);
    });

    test('shares are basis points that add up to exactly one', () {
      final r = fold([
        row(artistId: 'ar1', price: 1),
        row(artistId: 'ar2', price: 1),
        row(artistId: 'x', price: 1),
      ]);
      final shares = [
        for (final x in group0(r)['byArtist'] as List)
          ((x as Map)['share'] as num) * 10000,
      ];
      expect(shares.map((s) => s.round()).fold<int>(0, (a, b) => a + b), 10000);
      for (final s in shares) {
        expect(s.round(), anyOf(3333, 3334));
      }
    });

    test('previous is null without a comparison', () {
      final r = fold(
        [row(artistId: 'ar1')],
        previous: null,
        p: period(compare: RevenueCompareMode.none),
      );
      expect(group0(r)['previous'], isNull);
      expect(
        ((group0(r)['byArtist'] as List).single as Map)['previous'],
        isNull,
      );
    });
  });

  group('§3.4 — older bookings, estimated at read time', () {
    Map<String, dynamic> old(
      List<String> ids,
      num price, {
      String currency = 'XOF',
    }) =>
        row(serviceIds: ids, price: price, currency: currency)
          ..['serviceLines'] = null;

    double sumOf(List<RevenueLine> lines) =>
        lines.fold<double>(0, (a, l) => a + l.amount);

    test('proportional to today\'s prices; Σ = totalPrice', () {
      // s1 20 000, s2 5 000 → 4:1 of 30 000 = 24 000 + 6 000.
      final lines = revenueLinesOf(old(['s1', 's2'], 30000), catalogue);
      expect([for (final l in lines) l.amount], [24000, 6000]);
      expect(lines.every((l) => l.estimated), isTrue);
      expect(sumOf(lines), 30000);
    });

    test('all prices 0 (every service gone) → an equal split', () {
      final lines = revenueLinesOf(old(['gone1', 'gone2'], 10000), catalogue);
      expect([for (final l in lines) l.amount], [5000, 5000]);
    });

    test('a deleted service among live ones gets 0', () {
      final lines = revenueLinesOf(old(['s1', 'gone'], 10000), catalogue);
      expect([for (final l in lines) l.amount], [10000, 0]);
    });

    test('rounding to the unit; the remainder to the LARGEST line', () {
      // Three equal weights of 10 001 XOF → 3333.67 each → 3334 ×3 = 10 002;
      // the remainder (−1) goes to the largest — the first of equals.
      final lines = revenueLinesOf(
        old(['gone1', 'gone2', 'gone3'], 10001),
        catalogue,
      );
      expect(sumOf(lines), 10001);
      expect([for (final l in lines) l.amount], [3333, 3334, 3334]);

      // s2 5 000 : s3 15 000 : s1 20 000 = 1 : 3 : 4 of 1 004 → 125.5,
      // 376.5, 502 → 126 + 377 + 502 = 1 005; the −1 goes to s1, the LARGEST
      // line — the last here, so neither the first nor a rounded one.
      final three = revenueLinesOf(old(['s2', 's3', 's1'], 1004), catalogue);
      expect(sumOf(three), 1004);
      expect([for (final l in three) l.amount], [126, 377, 501]);
    });

    test('two decimals for a currency with a minor unit', () {
      final lines = revenueLinesOf(
        old(['gone1', 'gone2', 'gone3'], 10, currency: 'EUR'),
        catalogue,
      );
      expect(sumOf(lines), closeTo(10, 1e-9));
      expect([for (final l in lines) l.amount], [3.34, 3.33, 3.33]);
    });

    test('a single-service booking is exact, not marked estimated', () {
      final lines = revenueLinesOf(old(['s1'], 17000), catalogue);
      expect(lines.single.amount, 17000);
      expect(lines.single.estimated, isFalse);
    });

    test('kept lines are returned as kept', () {
      final lines = revenueLinesOf(
        row(
          serviceIds: ['s1', 's2'],
          price: 9,
          lines: [
            {'serviceId': 's1', 'name': 'a', 'price': 4},
            {'serviceId': 's2', 'name': 'b', 'price': 5},
          ],
        ),
        catalogue,
      );
      expect([for (final l in lines) l.amount], [4, 5]);
      expect(lines.any((l) => l.estimated), isFalse);
      expect(lines.first.keptName, 'a');
    });

    test('an estimated row says so; a total built on totalPrice does not', () {
      final r = fold([
        old(['s1', 's2'], 30000),
      ]);
      final g = group0(r);
      expect(
        (g['current'] as Map)['estimated'],
        isFalse,
        reason: 'Réalisé is the booking total, exact',
      );
      for (final x in g['byService'] as List) {
        expect((x as Map)['estimated'], isTrue);
      }
      expect(((g['byArtist'] as List).single as Map)['estimated'], isFalse);
    });
  });

  group('filters', () {
    final rows = [
      row(artistId: 'ar1', channel: 'app', price: 10000),
      row(artistId: null, channel: 'web', price: 3000),
      row(
        artistId: 'ar2',
        channel: 'salon',
        userId: 'manual',
        serviceIds: ['s1', 's2'],
        price: 25000,
        lines: [
          {'serviceId': 's1', 'name': 'x', 'price': 20000},
          {'serviceId': 's2', 'name': 'y', 'price': 5000},
        ],
      ),
    ];

    test('artistId=none: the unassigned bookings; the axis is []', () {
      final r = fold(
        rows,
        filters: const RevenueFilters(artistId: RevenueFilters.none),
      );
      expect(figures(r)['completedAmount'], 3000);
      expect(group0(r)['byArtist'], isEmpty);
      expect((r['filters'] as Map)['state'], 'unassigned');
    });

    test('an artist: its figures and its label', () {
      final r = fold(rows, filters: const RevenueFilters(artistId: 'ar2'));
      expect(figures(r)['completedAmount'], 25000);
      expect((r['filters'] as Map)['label'], 'Bintou');
      expect((r['filters'] as Map)['state'], 'active');
    });

    test('an unknown id: zero figures, no label, not an error', () {
      final r = fold(rows, filters: const RevenueFilters(artistId: 'nobody'));
      expect(r['groups'], isEmpty);
      expect((r['filters'] as Map)['label'], isNull);
      expect((r['filters'] as Map)['state'], 'removed');
    });

    test('a prestation: its LINES\' amounts, not the bookings\' totals', () {
      final r = fold(rows, filters: const RevenueFilters(serviceId: 's2'));
      final f = figures(r);
      expect(f['completedAmount'], 5000);
      expect(f['completedCount'], 1);
      expect(group0(r)['byService'], isEmpty);
      final byArtist = group0(r)['byArtist'] as List;
      expect(
        ((byArtist.single as Map)['current'] as Map)['completedAmount'],
        5000,
      );
    });

    test(
      'a prestation on an estimated booking makes the figures estimated',
      () {
        final r = fold([
          row(serviceIds: ['s1', 's2'], price: 30000)..['serviceLines'] = null,
        ], filters: const RevenueFilters(serviceId: 's2'));
        expect(figures(r)['completedAmount'], 6000);
        expect(figures(r)['estimated'], isTrue);
      },
    );

    test('a channel', () {
      final r = fold(rows, filters: const RevenueFilters(channel: 'salon'));
      expect(figures(r)['completedAmount'], 25000);
      expect(group0(r)['byChannel'], isEmpty);
      expect((r['filters'] as Map)['state'], 'active');
    });
  });

  group('the series', () {
    test('a month: a point per day, zero-filled, by salon day', () {
      final r = fold([
        row(at: DateTime.utc(2026, 11, 3, 9), price: 1000),
        row(at: DateTime.utc(2026, 11, 3, 17), price: 2000),
        row(at: DateTime.utc(2026, 11, 20, 9), price: 4000),
        row(status: 'confirmed', at: DateTime.utc(2026, 11, 20, 9)),
      ]);
      final series = group0(r)['series'] as List;
      expect(series, hasLength(30));
      expect(series[2], {
        'start': '2026-11-03',
        'end': '2026-11-03',
        'completedAmount': 3000,
        'completedCount': 2,
      });
      expect((series[19] as Map)['completedAmount'], 4000);
      expect((series[0] as Map)['completedAmount'], 0);
    });

    test('23:30 and 00:30 salon time land on their SALON days (Lagos, +1)', () {
      final p = period(
        tz: 'Africa/Lagos',
        at: DateTime.utc(2026, 11, 25, 13, 30),
      );
      final r = fold([
        // 23:30 Lagos on 9 November = 22:30 UTC on the 9th.
        row(at: DateTime.utc(2026, 11, 9, 22, 30), price: 1000),
        // 00:30 Lagos on 10 November = 23:30 UTC on the 9th.
        row(at: DateTime.utc(2026, 11, 9, 23, 30), price: 2000),
      ], p: p);
      final series = group0(r)['series'] as List;
      expect((series[8] as Map)['start'], '2026-11-09');
      expect((series[8] as Map)['completedAmount'], 1000);
      expect((series[9] as Map)['completedAmount'], 2000);
    });
  });

  test('the envelope: period, comparison, filters, asOf', () {
    final r = fold([row()]);
    expect(r['period'], 'month');
    expect(r['from'], '2026-11-01');
    expect(r['to'], '2026-11-30');
    expect(r['inProgress'], isTrue);
    expect(r['timezone'], 'Africa/Abidjan');
    expect(r['asOf'], '2026-11-25T14:30:00.000Z');
    expect(r['bucket'], 'day');
    expect(r['comparison'], {
      'mode': 'previous',
      'from': '2026-10-01',
      'to': '2026-10-31',
      'likeForLike': true,
      'cutoff': '2026-10-25T14:30:00.000Z',
    });
    expect(r['everCompleted'], isTrue);
  });
}

extension on Map<String, dynamic> {
  Map<String, dynamic> also(void Function(Map<String, dynamic>) f) {
    f(this);
    return this;
  }
}

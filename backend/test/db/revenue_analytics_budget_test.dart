@Tags(['postgres'])
library;

import 'dart:io';

import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/analytics/revenue_aggregator.dart';
import 'package:myweli_backend/src/analytics/revenue_analytics_service.dart';
import 'package:myweli_backend/src/analytics/revenue_period.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/clients/clients_repository.dart';
import 'package:myweli_backend/src/db/database.dart';
import 'package:myweli_backend/src/db/migrations.dart';
import 'package:myweli_backend/src/db/postgres_appointment_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// Every capability granted: the budget measures the reads and the fold,
/// not the membership lookup.
class _Owner extends MembershipService {
  _Owner()
    : super(
        InMemoryMembershipRepository(),
        InMemoryProviderAuthRepository(
          tokens: TokenService(secret: 'bench'),
          echoDevCode: false,
        ),
      );

  @override
  Future<bool> can(String accountId, String providerId, String capability) =>
      Future.value(true);
}

/// The budget of docs/design/pro-revenue-analytics.md §11, on a real
/// Postgres: a salon of 40 bookings a day, « Année » with a year comparison
/// (≈ 29 000 rows read) under 500 ms p95 server-side, « Mois » under 200 ms,
/// a ledger page under 200 ms. Over budget, the fold moves into SQL behind
/// the same service API (§9.1) — this test is the line that says when.
///
/// Its own database, so the 29 280 rows never meet another test's.
void main() {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    test(
      'revenue analytics budget (skipped — set DATABASE_URL to run)',
      () {},
      skip: 'requires DATABASE_URL',
    );
    return;
  }

  late Pool<void> pool;
  late RevenueAnalyticsService service;
  final ownDbName = 'myweli_revenue_${DateTime.now().microsecondsSinceEpoch}';
  // The last day of the seeded second year, mid-day: « Année » is in
  // progress, so the comparison is the like-for-like cut of the year before.
  final asOf = DateTime.utc(2026, 12, 31, 12);
  const perDay = 40;
  const days = 732; // 2025-01-01 → 2027-01-02

  setUpAll(() async {
    final admin = createPool(url);
    await admin.execute('CREATE DATABASE $ownDbName');
    await admin.close();
    pool = createPool(Uri.parse(url).replace(path: '/$ownDbName').toString());
    await withSchemaLock(pool, () => runMigrations(pool));
    // Production's shapes: `service_ids` as a JSON string inside jsonb, half
    // the rows with kept lines (R1) and half without (estimated), every
    // channel, eight collaborateurs, twenty prestations, three statuses.
    await pool.execute(
      Sql.named('''
INSERT INTO appointments
  (id, user_id, provider_id, service_ids, artist_id, appointment_date,
   duration_minutes, ends_at, status, total_price, currency, service_lines,
   channel, created_at)
SELECT 'bench-' || g,
       CASE WHEN g % 3 = 0 THEN 'manual' ELSE 'u' || (g % 500) END,
       'p_bench',
       to_jsonb(json_build_array('s' || (g % 20), 's' || ((g + 7) % 20))::text),
       'ar' || (g % 8),
       ts, 30, ts + interval '30 minutes',
       CASE WHEN g % 10 < 7 THEN 'completed'
            WHEN g % 10 < 9 THEN 'confirmed'
            ELSE 'noShow' END,
       10000 + (g % 7) * 1000,
       'XOF',
       CASE WHEN g % 2 = 0 THEN jsonb_build_array(
         jsonb_build_object('serviceId', 's' || (g % 20), 'name', 'S',
                            'price', 5000, 'durationMinutes', 15),
         jsonb_build_object('serviceId', 's' || ((g + 7) % 20), 'name', 'T',
                            'price', 5000 + (g % 7) * 1000,
                            'durationMinutes', 15)) END,
       CASE g % 4 WHEN 0 THEN 'web' WHEN 1 THEN 'app' WHEN 2 THEN 'salon'
            ELSE NULL END,
       now()
  FROM generate_series(0, @n - 1) AS g,
       LATERAL (SELECT timestamptz '2025-01-01 08:00+00'
                       + (g / @per_day) * interval '1 day'
                       + (g % @per_day) * interval '15 minutes' AS ts) t'''),
      parameters: {'n': perDay * days, 'per_day': perDay},
    );
    final salon = {
      'id': 'p_bench',
      'currency': 'XOF',
      'timezone': 'Africa/Abidjan',
      'services': [
        for (var i = 0; i < 20; i++)
          {'id': 's$i', 'name': 'Prestation $i', 'price': 5000 + i * 500},
      ],
      'artists': [
        for (var i = 0; i < 6; i++) {'id': 'ar$i', 'name': 'Collaborateur $i'},
      ],
    };
    service = RevenueAnalyticsService(
      _Owner(),
      PostgresAppointmentRepository(pool),
      InMemoryProvidersRepository([salon]),
      InMemoryClientsRepository(),
      clock: () => asOf,
    );
  });

  tearDownAll(() async {
    await pool.close();
    final admin = createPool(url);
    await admin.execute('DROP DATABASE IF EXISTS $ownDbName WITH (FORCE)');
    await admin.close();
  });

  /// The p95 of [runs] timed calls, after two untimed ones.
  Future<Duration> p95(Future<void> Function() call, {int runs = 20}) async {
    await call();
    await call();
    final times = <int>[];
    for (var i = 0; i < runs; i++) {
      final sw = Stopwatch()..start();
      await call();
      times.add(sw.elapsedMicroseconds);
    }
    times.sort();
    return Duration(microseconds: times[(runs * 0.95).ceil() - 1]);
  }

  test('« Année » with the year before: ~29 000 rows, < 500 ms p95', () async {
    const q = RevenueQuery(
      kind: RevenuePeriodKind.year,
      compare: RevenueCompareMode.year,
    );
    final r = await service.revenue('owner', 'p_bench', q);
    expect(r.error, isNull);
    final group = (r.data!['groups'] as List).single as Map;
    // The control: the read really is the size the budget is about.
    final current = group['current'] as Map;
    final previous = group['previous'] as Map;
    final read = [current, previous].fold<int>(
      0,
      (a, f) =>
          a +
          (f['completedCount'] as int) +
          (f['upcomingCount'] as int) +
          (f['toCloseCount'] as int) +
          (f['noShowCount'] as int),
    );
    expect(read, greaterThan(28000));

    final t = await p95(() => service.revenue('owner', 'p_bench', q));
    stdout.writeln('revenue year+year p95: ${t.inMilliseconds} ms');
    expect(t, lessThan(const Duration(milliseconds: 500)));
  });

  test('« Mois »: < 200 ms p95', () async {
    const q = RevenueQuery(kind: RevenuePeriodKind.month);
    final t = await p95(() => service.revenue('owner', 'p_bench', q));
    stdout.writeln('revenue month p95: ${t.inMilliseconds} ms');
    expect(t, lessThan(const Duration(milliseconds: 200)));
  });

  test('a ledger page, filtered by prestation: < 200 ms p95', () async {
    const q = RevenueQuery(
      kind: RevenuePeriodKind.year,
      filters: RevenueFilters(serviceId: 's3'),
    );
    final first = await service.ledger(
      'owner',
      'p_bench',
      q,
      status: RevenueLedgerStatus.completed,
      page: 1,
      pageSize: 50,
    );
    expect(first.error, isNull);
    expect(first.data!['total'], greaterThan(1000));
    final t = await p95(
      () => service.ledger(
        'owner',
        'p_bench',
        q,
        status: RevenueLedgerStatus.completed,
        page: 10,
        pageSize: 50,
      ),
    );
    stdout.writeln('ledger page p95: ${t.inMilliseconds} ms');
    expect(t, lessThan(const Duration(milliseconds: 200)));
  });
}

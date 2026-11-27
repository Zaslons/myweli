import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/utils/app_locale.dart';
import 'package:myweli/core/utils/revenue_periods.dart';
import 'package:myweli/core/utils/revenue_wording.dart';
import 'package:myweli/models/revenue_analytics.dart';

/// The model reads **the R2 server's own answers**, not only the fixtures
/// written from the contract (docs/design/pro-revenue-analytics.md §13.2,
/// §21.2).
///
/// `test/support/revenue_r2/` holds bodies answered on 2026-11-27 by the
/// backend of `main` (R2, built with `dart_frog build`) on a throwaway local
/// Postgres: a demo salon with three collaborateurs, five prestations, and
/// the agenda the real weekly reset generates (`DemoResetService`). The
/// demo account signed in through the demo seam. Nothing from production.
void main() {
  setUpAll(() async {
    await initializeDateFormatting(kAppLocale, null);
    initAppLocale();
  });

  Map<String, dynamic> read(String name) =>
      jsonDecode(File('test/support/revenue_r2/$name.json').readAsStringSync())
          as Map<String, dynamic>;

  for (final name in [
    'analytics_month',
    'analytics_week',
    'analytics_year',
    'analytics_custom_from_2026-10-01_to_2026-11-27',
    'analytics_month_service_svc-Tresses',
  ]) {
    test('$name: parsed whole, and every word of the screen built', () {
      final a = RevenueAnalytics.fromJson(read(name));
      expect(a.groups, isNotEmpty, reason: 'the demo salon has figures');
      expect(revenuePeriodTitle(a), isNotEmpty);
      final g = a.groups.first;
      expect(g.currency, 'XOF');
      expect(g.series, isNotEmpty);
      for (final axis in RevenueAxis.values) {
        for (final row in g.rowsOf(axis)) {
          expect(revenueLabelOf(axis, row), isNotEmpty, reason: '$axis');
        }
      }
      expect(
        previousRevenuePeriod(a, const RevenueQuery()),
        isNotNull,
        reason: 'November 2026 can step back',
      );
    });
  }

  test(
    'the month: three collaborateurs and « Sans collaborateur attribué »',
    () {
      final a = RevenueAnalytics.fromJson(read('analytics_month'));
      expect(a.inProgress, isTrue);
      expect(a.comparison.likeForLike, isTrue);
      final labels = [
        for (final r in a.groups.single.byArtist)
          revenueLabelOf(RevenueAxis.artist, r),
      ];
      expect(
        labels,
        containsAll(['Adjoua K.', 'Salimata O.', 'Koffi A.', kNoArtistLabel]),
      );
      expect(
        a.groups.single.byChannel.single.key,
        'salon',
        reason: 'the demo agenda is entered by the salon (bookManual)',
      );
    },
  );

  test('a prestation’s detail: its axis is empty, its filter echoed', () {
    final a = RevenueAnalytics.fromJson(
      read('analytics_month_service_svc-Tresses'),
    );
    expect(a.filters.serviceId, 'svc-Tresses');
    expect(revenueFilterLabel(RevenueAxis.service, a.filters), 'Tresses');
    expect(a.groups.single.byService, isEmpty);
    expect(a.comparison.mode, RevenueCompare.none);
    expect(a.groups.single.previous, isNull);
  });

  test('the ledger pages, « completed » and « toClose »', () {
    final done = RevenueLedgerPage.fromJson(read('ledger_completed'));
    expect(done.pageSize, 5);
    expect(done.items, hasLength(5));
    expect(done.total, greaterThan(5));
    for (final row in done.items) {
      expect(row.status, 'completed');
      expect(revenueLedgerLine(row), isNotEmpty);
    }
    final toClose = RevenueLedgerPage.fromJson(read('ledger_toclose'));
    expect(toClose.items, isNotEmpty);
    expect(toClose.items.every((r) => r.status == 'confirmed'), isTrue);
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/revenue_analytics.dart';
import 'package:myweli/providers/pro_revenue_provider.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';

import '../support/revenue_fixtures.dart';

/// docs/design/pro-revenue-analytics.md §13.2 — `ProRevenueProvider`:
/// period stepping keeps one view per screen, a late answer is dropped, a
/// salon switch empties everything, a 403 is the refused state (no retry),
/// a failure retries the same period, the ledger pages.
class _Held extends MockProService {
  final analytics = <Completer<ApiResponse<RevenueAnalytics>>>[];
  final ledgers = <Completer<ApiResponse<RevenueLedgerPage>>>[];
  final asked = <RevenueQuery>[];
  final pages = <int>[];

  @override
  Future<ApiResponse<RevenueAnalytics>> getRevenueAnalytics(
    SalonId providerId,
    RevenueQuery query,
  ) {
    asked.add(query);
    final c = Completer<ApiResponse<RevenueAnalytics>>();
    analytics.add(c);
    return c.future;
  }

  @override
  Future<ApiResponse<RevenueLedgerPage>> getRevenueLedger(
    SalonId providerId,
    RevenueQuery query, {
    RevenueLedgerStatus status = RevenueLedgerStatus.completed,
    int page = 1,
    int pageSize = 20,
    DateTime? asOf,
  }) {
    pages.add(page);
    final c = Completer<ApiResponse<RevenueLedgerPage>>();
    ledgers.add(c);
    return c.future;
  }
}

ApiResponse<RevenueAnalytics> _answer({String from = '2026-11-01'}) =>
    ApiResponse.success(
      RevenueAnalytics.fromJson(revenueAnalyticsJson(from: from)),
    );

void main() {
  const salon = SalonId('provider1');
  late _Held service;
  late ProRevenueProvider p;

  setUp(() {
    service = _Held();
    p = ProRevenueProvider(service: service);
  });

  test('a load empties the view first: never the old figures under the new '
      'period', () async {
    final first = p.load(salon, 'k', const RevenueQuery());
    service.analytics.last.complete(_answer());
    await first;
    expect(p.view('k')!.analytics, isNotNull);

    const week = RevenueQuery(period: RevenuePeriod.week);
    unawaited(p.load(salon, 'k', week));
    expect(p.view('k')!.query, week);
    expect(p.view('k')!.isLoading, isTrue);
    expect(p.view('k')!.analytics, isNull);
  });

  test('a late answer is dropped: the newer request wins', () async {
    final older = p.load(salon, 'k', const RevenueQuery());
    const week = RevenueQuery(period: RevenuePeriod.week);
    final newer = p.load(salon, 'k', week);
    service.analytics[1].complete(_answer(from: '2026-11-23'));
    await newer;
    service.analytics[0].complete(_answer(from: '2026-10-01'));
    await older;
    expect(p.view('k')!.query, week);
    expect(p.view('k')!.analytics!.from, revenueDay(2026, 11, 23));
  });

  test(
    'views are per screen: a detail does not overwrite « Revenus »',
    () async {
      final main = p.load(salon, 'revenus', const RevenueQuery());
      service.analytics.last.complete(_answer());
      await main;
      final detail = p.load(
        salon,
        'artist:a1',
        const RevenueQuery().filteredOn(RevenueAxis.artist, 'a1'),
      );
      expect(p.view('revenus')!.analytics, isNotNull);
      service.analytics.last.complete(_answer());
      await detail;
      expect(p.view('revenus')!.query.artistId, isNull);
    },
  );

  test(
    'a salon switch empties everything and drops the answer in flight',
    () async {
      final pending = p.load(salon, 'k', const RevenueQuery());
      p.resetForSalonSwitch();
      expect(p.view('k'), isNull);
      service.analytics.last.complete(_answer());
      await pending;
      expect(p.view('k'), isNull, reason: 'the previous salon’s answer');
    },
  );

  test('403: refused, no error to retry', () async {
    for (final code in ['forbidden', 'not_a_member']) {
      final f = p.load(salon, code, const RevenueQuery());
      service.analytics.last.complete(
        ApiResponse.error('Action non autorisée pour ce salon.', code: code),
      );
      await f;
      expect(p.view(code)!.refused, isTrue, reason: code);
      expect(p.view(code)!.loadError, isNull, reason: code);
    }
  });

  test(
    'a failure: the error, then « Réessayer » asks the SAME period',
    () async {
      final q = RevenueQuery(
        period: RevenuePeriod.day,
        date: revenueDay(2026, 11, 3),
      );
      final f = p.load(salon, 'k', q);
      service.analytics.last.complete(
        ApiResponse.error('Pas de connexion. Réessayez.', code: 'network'),
      );
      await f;
      expect(p.view('k')!.loadError, 'Pas de connexion. Réessayez.');
      expect(p.view('k')!.refused, isFalse);
      final r = p.retry(salon, 'k');
      expect(service.asked.last, q);
      service.analytics.last.complete(_answer());
      await r;
      expect(p.view('k')!.loadError, isNull);
    },
  );

  test('a thrown answer is a failure, not a crash', () async {
    final f = p.load(salon, 'k', const RevenueQuery());
    service.analytics.last.completeError(StateError('offline'));
    await f;
    expect(p.view('k')!.loadError, isNotNull);
  });

  test('the currency choice survives a period change', () async {
    final f = p.load(salon, 'k', const RevenueQuery());
    service.analytics.last.complete(_answer());
    await f;
    p.chooseCurrency('k', 'XAF');
    unawaited(
      p.load(salon, 'k', const RevenueQuery(period: RevenuePeriod.year)),
    );
    expect(p.view('k')!.currency, 'XAF');
  });

  test('the comparison is the session’s', () {
    expect(p.compare, RevenueCompare.previous);
    p.setCompare(RevenueCompare.year);
    expect(p.compare, RevenueCompare.year);
  });

  group('the ledger', () {
    RevenueLedgerPage page(int n, {int total = 48}) =>
        RevenueLedgerPage.fromJson(
          revenueLedgerJson(
            items: [for (var i = 0; i < n; i++) revenueLedgerRow(id: 'a$i')],
            total: total,
          ),
        );

    test('pages of 20, « Afficher plus » appends the next', () async {
      final first = p.loadLedger(
        salon,
        'l',
        const RevenueQuery(),
        RevenueLedgerStatus.completed,
      );
      service.ledgers.last.complete(ApiResponse.success(page(20)));
      await first;
      expect(p.ledger('l')!.hasMore, isTrue);
      final more = p.loadMoreLedger(salon, 'l');
      expect(p.ledger('l')!.isLoadingMore, isTrue);
      service.ledgers.last.complete(ApiResponse.success(page(20)));
      await more;
      expect(service.pages, [1, 2]);
      expect(p.ledger('l')!.items, hasLength(40));
      expect(p.ledger('l')!.page, 2);
    });

    test('a failed page keeps the rows; the error sits under them', () async {
      final first = p.loadLedger(
        salon,
        'l',
        const RevenueQuery(),
        RevenueLedgerStatus.completed,
      );
      service.ledgers.last.complete(ApiResponse.success(page(20)));
      await first;
      final more = p.loadMoreLedger(salon, 'l');
      service.ledgers.last.complete(ApiResponse.error('Pas de connexion.'));
      await more;
      expect(p.ledger('l')!.items, hasLength(20));
      expect(p.ledger('l')!.moreError, 'Pas de connexion.');
      expect(p.ledger('l')!.loadError, isNull);
    });

    test(
      'the page’s asOf is kept, so later pages measure the same instant',
      () async {
        final first = p.loadLedger(
          salon,
          'l',
          const RevenueQuery(),
          RevenueLedgerStatus.toClose,
        );
        service.ledgers.last.complete(ApiResponse.success(page(20)));
        await first;
        expect(p.ledger('l')!.asOf, DateTime.utc(2026, 11, 25, 14, 30));
      },
    );

    test('nothing more when everything is shown', () async {
      final first = p.loadLedger(
        salon,
        'l',
        const RevenueQuery(),
        RevenueLedgerStatus.completed,
      );
      service.ledgers.last.complete(ApiResponse.success(page(3, total: 3)));
      await first;
      await p.loadMoreLedger(salon, 'l');
      expect(service.pages, [1]);
    });
  });
}

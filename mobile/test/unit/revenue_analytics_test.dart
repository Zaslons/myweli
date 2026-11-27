import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/utils/app_locale.dart';
import 'package:myweli/core/utils/revenue_periods.dart';
import 'package:myweli/core/utils/revenue_wording.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/revenue_analytics.dart';
import 'package:myweli/services/mock/mock_revenue.dart';

import '../support/revenue_fixtures.dart';

/// docs/design/pro-revenue-analytics.md §13.2 — the app's half: the model
/// reads the contract, the period bar steps from the server's answer, the
/// words of §3.3 / §3.6 / §4.13, and the mock folds by the server's rules.
void main() {
  setUpAll(() async {
    await initializeDateFormatting(kAppLocale, null);
    initAppLocale();
  });

  RevenueAnalytics answer({
    String period = 'month',
    String from = '2026-11-01',
    String to = '2026-11-30',
    bool inProgress = true,
    String asOf = '2026-11-25T14:30:00.000Z',
    String compareMode = 'previous',
  }) => RevenueAnalytics.fromJson(
    revenueAnalyticsJson(
      period: period,
      from: from,
      to: to,
      inProgress: inProgress,
      asOf: asOf,
      compareMode: compareMode,
    ),
  );

  group('the model reads the contract', () {
    test('every part of an answer', () {
      final a = answer();
      expect(a.period, RevenuePeriod.month);
      expect(a.from, revenueDay(2026, 11, 1));
      expect(a.to, revenueDay(2026, 11, 30));
      expect(a.days, 30);
      expect(a.asOf, DateTime.utc(2026, 11, 25, 14, 30));
      expect(a.comparison.likeForLike, isTrue);
      expect(a.comparison.cutoff, DateTime.utc(2026, 10, 25, 14, 30));
      final g = a.groups.single;
      expect(g.currency, 'XOF');
      expect(g.current.completedAmount, 1250000);
      expect(g.current.noShowRate, closeTo(0.0588, 1e-9));
      expect(g.previous!.completedCount, 46);
      expect(g.series, hasLength(30));
      expect(g.byArtist[3].key, isNull);
      expect(g.byArtist[3].state, RevenueRowState.unassigned);
      expect(g.byService.first.estimated, isTrue);
      expect(g.byChannel.last.state, RevenueRowState.legacy);
    });

    test('a ledger page, with and without the client name', () {
      final page = RevenueLedgerPage.fromJson(
        revenueLedgerJson(
          items: [
            revenueLedgerRow(),
            revenueLedgerRow(
              id: 'a2',
              client: null,
              services: [null, 'Nattes'],
            ),
          ],
          total: 48,
        ),
      );
      expect(page.total, 48);
      expect(page.items.first.clientDisplayName, 'Fatou B.');
      expect(page.items.last.clientDisplayName, isNull);
      expect(page.items.last.serviceNames, [null, 'Nattes']);
    });

    test('strict: a body without its parts throws (→ unreadable)', () {
      final body = revenueAnalyticsJson()..remove('groups');
      expect(() => RevenueAnalytics.fromJson(body), throwsA(isA<TypeError>()));
      final figures = revenueAnalyticsJson();
      ((figures['groups'] as List).first as Map)['current'] =
          <String, dynamic>{};
      expect(
        () => RevenueAnalytics.fromJson(figures),
        throwsA(isA<TypeError>()),
      );
    });

    test('strict: an unknown enum value or a date that is not one throws', () {
      expect(
        () => RevenueAnalytics.fromJson(revenueAnalyticsJson(period: 'decade')),
        throwsFormatException,
      );
      expect(() => parseRevenueDay('2026-02-30'), throwsFormatException);
      expect(() => parseRevenueDay('2026-2-3'), throwsFormatException);
      expect(parseRevenueDay('2024-02-29'), revenueDay(2024, 2, 29));
    });
  });

  group('the query', () {
    test('the parameters of §7.1', () {
      expect(const RevenueQuery().toQueryParameters(), {
        'period': 'month',
        'compare': 'previous',
      });
      final custom = RevenueQuery(
        period: RevenuePeriod.custom,
        from: revenueDay(2026, 10, 3),
        to: revenueDay(2026, 11, 25),
        compare: RevenueCompare.year,
      );
      expect(custom.toQueryParameters(), {
        'period': 'custom',
        'from': '2026-10-03',
        'to': '2026-11-25',
        'compare': 'year',
      });
      final unassigned = const RevenueQuery().filteredOn(
        RevenueAxis.artist,
        null,
      );
      expect(unassigned.toQueryParameters()['artistId'], 'none');
      final channel = const RevenueQuery().filteredOn(
        RevenueAxis.channel,
        'web',
      );
      expect(channel.toQueryParameters()['channel'], 'web');
      expect(channel.filterAxis, RevenueAxis.channel);
    });

    test('a route query round-trips; a malformed one is the current month', () {
      final q = RevenueQuery(
        period: RevenuePeriod.week,
        date: revenueDay(2026, 11, 25),
        compare: RevenueCompare.none,
      );
      expect(RevenueQuery.fromRouteQuery(q.toRouteQuery()), q);
      for (final bad in [
        {'period': 'decade'},
        {'period': 'custom', 'from': '2026-11-25', 'to': '2026-11-01'},
        {'period': 'custom', 'from': '2024-01-01', 'to': '2026-01-01'},
        {'period': 'week', 'date': 'hier'},
      ]) {
        final r = RevenueQuery.fromRouteQuery(bad);
        expect(
          r.period,
          bad['period'] == 'week' ? RevenuePeriod.week : RevenuePeriod.month,
        );
        expect(r.date, isNull, reason: '$bad');
      }
    });
  });

  group('the period bar steps from the answer (§3.5, §4.3)', () {
    const q = RevenueQuery();

    test('‹ and › one unit, by kind', () {
      final month = answer();
      expect(previousRevenuePeriod(month, q)!.date, revenueDay(2026, 10, 1));
      expect(nextRevenuePeriod(month, q)!.date, revenueDay(2026, 12, 1));

      final jan = answer(
        from: '2026-01-01',
        to: '2026-01-31',
        inProgress: false,
      );
      expect(previousRevenuePeriod(jan, q)!.date, revenueDay(2025, 12, 1));

      final week = answer(period: 'week', from: '2026-11-23', to: '2026-11-29');
      expect(previousRevenuePeriod(week, q)!.date, revenueDay(2026, 11, 16));
      expect(nextRevenuePeriod(week, q)!.date, revenueDay(2026, 11, 30));

      final day = answer(period: 'day', from: '2026-11-25', to: '2026-11-25');
      expect(previousRevenuePeriod(day, q)!.date, revenueDay(2026, 11, 24));

      final year = answer(period: 'year', from: '2026-01-01', to: '2026-12-31');
      expect(previousRevenuePeriod(year, q)!.date, revenueDay(2025, 1, 1));
    });

    test('a custom range steps by its own length', () {
      final custom = answer(
        period: 'custom',
        from: '2026-11-01',
        to: '2026-11-10',
      );
      final prev = previousRevenuePeriod(custom, q)!;
      expect(prev.from, revenueDay(2026, 10, 22));
      expect(prev.to, revenueDay(2026, 10, 31));
      final next = nextRevenuePeriod(custom, q)!;
      expect(next.from, revenueDay(2026, 11, 11));
      expect(next.to, revenueDay(2026, 11, 20));
    });

    test(
      '‹ stops at 2020; the week of 1 January 2020 is asked by that day',
      () {
        final week = answer(
          period: 'week',
          from: '2020-01-06',
          to: '2020-01-12',
          inProgress: false,
        );
        expect(previousRevenuePeriod(week, q)!.date, revenueDay(2020, 1, 1));
        final first = answer(
          period: 'week',
          from: '2019-12-30',
          to: '2020-01-05',
          inProgress: false,
        );
        expect(previousRevenuePeriod(first, q), isNull);
        final jan2020 = answer(
          from: '2020-01-01',
          to: '2020-01-31',
          inProgress: false,
        );
        expect(previousRevenuePeriod(jan2020, q), isNull);
      },
    );

    test('› stops at the salon’s today + 366 days, read from asOf', () {
      // asOf 2026-11-25 → the last day is 2027-11-26.
      final nov2027 = answer(
        from: '2027-11-01',
        to: '2027-11-30',
        inProgress: false,
      );
      expect(nextRevenuePeriod(nov2027, q), isNull);
      final oct2027 = answer(
        from: '2027-10-01',
        to: '2027-10-31',
        inProgress: false,
      );
      expect(nextRevenuePeriod(oct2027, q)!.date, revenueDay(2027, 11, 1));
    });

    test(
      'another kind keeps the anchor: today when in progress, else from',
      () {
        expect(
          switchRevenuePeriod(answer(), q, RevenuePeriod.week).date,
          isNull,
          reason: 'in progress → the server’s today',
        );
        final past = answer(
          from: '2026-09-01',
          to: '2026-09-30',
          inProgress: false,
        );
        expect(
          switchRevenuePeriod(past, q, RevenuePeriod.week).date,
          revenueDay(2026, 9, 1),
        );
        expect(switchRevenuePeriod(null, q, RevenuePeriod.day).date, isNull);
      },
    );

    test('« Dates… » errors under « Au »', () {
      expect(
        customRangeError(revenueDay(2026, 11, 2), revenueDay(2026, 11, 1)),
        'La date de fin précède la date de début',
      );
      expect(
        customRangeError(revenueDay(2025, 1, 1), revenueDay(2026, 1, 2)),
        '366 jours au plus',
      );
      expect(
        customRangeError(revenueDay(2025, 1, 1), revenueDay(2026, 1, 1)),
        isNull,
        reason: '366 days counting both ends: allowed',
      );
    });
  });

  group('the titles', () {
    test('one per kind (§4.3)', () {
      expect(revenuePeriodTitle(answer()), 'Novembre 2026');
      expect(
        revenuePeriodTitle(
          answer(period: 'day', from: '2026-11-25', to: '2026-11-25'),
        ),
        'Mercredi 25 novembre',
      );
      expect(
        revenuePeriodTitle(
          answer(
            period: 'day',
            from: '2025-11-24',
            to: '2025-11-24',
            inProgress: false,
          ),
        ),
        'Lundi 24 novembre 2025',
      );
      expect(
        revenuePeriodTitle(
          answer(period: 'week', from: '2026-11-23', to: '2026-11-29'),
        ),
        '23 – 29 nov. 2026',
      );
      expect(
        revenuePeriodTitle(
          answer(period: 'week', from: '2025-12-29', to: '2026-01-04'),
        ),
        '29 déc. 2025 – 4 janv. 2026',
      );
      expect(
        revenuePeriodTitle(
          answer(period: 'year', from: '2026-01-01', to: '2026-12-31'),
        ),
        '2026',
      );
      expect(
        revenuePeriodTitle(
          answer(period: 'custom', from: '2026-10-03', to: '2026-11-25'),
        ),
        '3 oct. – 25 nov. 2026',
      );
    });

    test('the comparison: like for like, a whole month, none', () {
      expect(
        revenueComparisonLabel(answer()),
        '1er – 25 oct. 2026, même avancement',
      );
      expect(
        revenueComparisonLabel(
          answer(from: '2026-11-01', to: '2026-11-30', inProgress: false),
        ),
        'octobre 2026',
      );
      expect(revenueComparisonLabel(answer(compareMode: 'none')), isNull);
    });
  });

  group('the deltas of §3.6', () {
    test('percent, stable, nouveau, nothing', () {
      expect(revenueDelta(112, 100)!.text, '+12 %');
      expect(revenueDelta(92, 100)!.text, '−8 %');
      expect(revenueDelta(1004, 1000)!.text, 'stable');
      expect(revenueDelta(1004, 1000)!.up, isNull);
      expect(revenueDelta(5, 0)!.text, 'nouveau');
      expect(revenueDelta(0, 0), isNull);
      expect(revenueDelta(5, null), isNull, reason: 'no comparison');
    });

    test('the colour follows the good direction, never alone', () {
      expect(revenueDelta(112, 100)!.tone, RevenueDeltaTone.good);
      expect(revenueDelta(92, 100)!.tone, RevenueDeltaTone.bad);
      expect(revenueDelta(92, 100)!.up, isFalse);
      expect(
        revenueDelta(112, 100, comparison: 'octobre 2026')!.spoken,
        'en hausse de 12 % par rapport à octobre 2026',
      );
    });

    test('the no-show rate: points, one decimal, up is bad', () {
      final d = revenueRateDelta(0.059, 0.071, comparison: 'octobre 2026')!;
      expect(d.text, '−1,2 pt');
      expect(d.tone, RevenueDeltaTone.good);
      expect(d.spoken, 'en baisse de 1,2 point par rapport à octobre 2026');
      expect(revenueRateDelta(0.08, 0.05)!.tone, RevenueDeltaTone.bad);
      expect(revenueRateDelta(0.0501, 0.05)!.text, 'stable');
      expect(revenueRateDelta(null, 0.05), isNull);
    });
  });

  group('the labels of §3.3, row by row', () {
    String label(RevenueAxis axis, String? key, String? name, String state) =>
        revenueRowLabel(
          axis,
          key: key,
          label: name,
          state: RevenueRowState.values.byName(state),
        );

    test('collaborateurs', () {
      expect(label(RevenueAxis.artist, 'a1', 'Awa Koné', 'active'), 'Awa Koné');
      expect(
        label(RevenueAxis.artist, 'a1', 'Awa Koné', 'removed'),
        'Awa Koné · a quitté l’équipe',
      );
      expect(
        label(RevenueAxis.artist, 'a1', null, 'removed'),
        'Ancien collaborateur',
      );
      expect(
        label(RevenueAxis.artist, null, null, 'unassigned'),
        'Sans collaborateur attribué',
      );
    });

    test('prestations', () {
      expect(label(RevenueAxis.service, 's1', 'Tresses', 'active'), 'Tresses');
      expect(
        label(RevenueAxis.service, 's1', 'Nattes', 'removed'),
        'Nattes · prestation supprimée',
      );
      expect(
        label(RevenueAxis.service, 's1', null, 'removed'),
        'Prestation supprimée',
      );
    });

    test('canaux', () {
      expect(
        label(RevenueAxis.channel, 'app', null, 'active'),
        'Application MyWeli',
      );
      expect(label(RevenueAxis.channel, 'web', null, 'active'), 'Site MyWeli');
      expect(
        label(RevenueAxis.channel, 'salon', null, 'active'),
        'Ajouté par le salon',
      );
      expect(
        label(RevenueAxis.channel, 'online', null, 'legacy'),
        'En ligne (avant le suivi)',
      );
    });

    test('a ledger row: « Client » and « Sans collaborateur » by default', () {
      final row = RevenueLedgerRow.fromJson(
        revenueLedgerRow(
          client: null,
          services: ['Tresses', null],
          artistLabel: null,
          artistState: 'unassigned',
        ),
      );
      expect(
        revenueLedgerLine(row),
        'Client · Tresses, Prestation supprimée · Sans collaborateur',
      );
    });

    test('nothing claims a payment — « encaiss » only in the negation', () {
      for (final text in [
        kRevenuePriceFootnote,
        kRevenueServicesFootnote,
        kRevenueEstimatedFootnote,
      ]) {
        if (text.contains('encaiss')) {
          expect(text, contains('MyWeli n’encaisse rien'));
        }
        expect(text, isNot(contains('chiffre d’affaires')));
        expect(text, isNot(contains('paiements reçus')));
      }
    });
  });

  group('the mock folds by the server’s rules', () {
    const salon = SalonId('provider1');
    final now = DateTime.utc(2026, 3, 11, 10, 30);

    tearDown(() => MockRevenueWorld.twoCurrencies = false);

    test('a salon with no history: everCompleted false, no group', () {
      final r = MockRevenueWorld.analytics(
        const SalonId('provider2'),
        const RevenueQuery(),
        now,
      );
      expect(r.data!.everCompleted, isFalse);
      expect(r.data!.groups, isEmpty);
    });

    test('the ledger lists exactly what the figures count', () {
      for (final q in [
        const RevenueQuery(),
        const RevenueQuery(period: RevenuePeriod.year),
        const RevenueQuery().filteredOn(RevenueAxis.artist, 'artist1'),
        const RevenueQuery().filteredOn(RevenueAxis.service, 'service1'),
      ]) {
        final a = MockRevenueWorld.analytics(salon, q, now).data!;
        final f = a.groups.single.current;
        for (final (status, count) in [
          (RevenueLedgerStatus.completed, f.completedCount),
          (RevenueLedgerStatus.upcoming, f.upcomingCount),
          (RevenueLedgerStatus.toClose, f.toCloseCount),
          (RevenueLedgerStatus.noShow, f.noShowCount),
          (RevenueLedgerStatus.cancelled, f.cancelledCount),
        ]) {
          final page = MockRevenueWorld.ledger(
            salon,
            q,
            status,
            1,
            50,
            now,
            a.asOf,
          ).data!;
          expect(page.total, count, reason: '$q $status');
        }
      }
    });

    test('a booking under way is « Prévu », in the figures AND the ledger '
        '(À clôturer goes by the END, §3.2)', () {
      // Find a confirmed booking that starts after 10:00 on some day, then
      // stand one minute after its start: it is under way.
      RevenueLedgerRow? row;
      DateTime? day;
      for (var i = 0; i < 60 && row == null; i++) {
        final d = DateTime.utc(2026, 3, 11).add(Duration(days: i));
        final at = DateTime.utc(d.year, d.month, d.day, 10);
        final upcoming = MockRevenueWorld.ledger(
          salon,
          RevenueQuery(period: RevenuePeriod.day, date: d),
          RevenueLedgerStatus.upcoming,
          1,
          50,
          at,
          at,
        ).data!;
        row = upcoming.items
            .where((r) => !r.appointmentDate.isBefore(at))
            .firstOrNull;
        day = d;
      }
      expect(row, isNotNull, reason: 'the mock world has such a booking');
      final now = row!.appointmentDate.add(const Duration(minutes: 1));
      final q = RevenueQuery(period: RevenuePeriod.day, date: day);
      final f = MockRevenueWorld.analytics(salon, q, now).data!.groups.single;
      int total(RevenueLedgerStatus s) =>
          MockRevenueWorld.ledger(salon, q, s, 1, 50, now, now).data!.total;
      expect(total(RevenueLedgerStatus.toClose), f.current.toCloseCount);
      expect(total(RevenueLedgerStatus.upcoming), f.current.upcomingCount);
      expect(
        MockRevenueWorld.ledger(
          salon,
          q,
          RevenueLedgerStatus.upcoming,
          1,
          50,
          now,
          now,
        ).data!.items.map((r) => r.appointmentId),
        contains(row.appointmentId),
      );
    });

    test('shares add up to 1; the filtered axis is empty', () {
      final a = MockRevenueWorld.analytics(
        salon,
        const RevenueQuery(period: RevenuePeriod.year),
        now,
      ).data!;
      for (final axis in RevenueAxis.values) {
        final rows = a.groups.single.rowsOf(axis);
        expect(rows, isNotEmpty, reason: '$axis');
        expect(
          rows.fold<double>(0, (s, r) => s + r.share),
          closeTo(1, 1e-9),
          reason: '$axis',
        );
      }
      final detail = MockRevenueWorld.analytics(
        salon,
        const RevenueQuery().filteredOn(RevenueAxis.artist, 'artist1'),
        now,
      ).data!;
      expect(detail.groups.single.byArtist, isEmpty);
      expect(detail.filters.label, 'Kouassi Jean');
    });

    test('two currencies: two groups, never one sum', () {
      MockRevenueWorld.twoCurrencies = true;
      final a = MockRevenueWorld.analytics(
        salon,
        const RevenueQuery(period: RevenuePeriod.year),
        now,
      ).data!;
      expect(a.groups.map((g) => g.currency), ['XOF', 'XAF']);
    });

    test('out of bounds: the server’s codes', () {
      expect(
        MockRevenueWorld.analytics(
          salon,
          RevenueQuery(
            period: RevenuePeriod.custom,
            from: revenueDay(2024, 1, 1),
            to: revenueDay(2025, 6, 1),
          ),
          now,
        ).error,
        'range_too_long',
      );
      expect(
        MockRevenueWorld.analytics(
          salon,
          RevenueQuery(date: revenueDay(2019, 6, 1)),
          now,
        ).error,
        'invalid_input',
      );
    });
  });
}

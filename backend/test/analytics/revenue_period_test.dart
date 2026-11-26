import 'package:myweli_backend/src/analytics/revenue_period.dart';
import 'package:test/test.dart';

/// The calendar of the revenue analytics —
/// docs/design/pro-revenue-analytics.md §3.5, §13.1 (« Period resolution »).
void main() {
  DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

  ResolvedRevenuePeriod resolve(
    RevenuePeriodKind kind, {
    RevenueCompareMode compare = RevenueCompareMode.previous,
    DateTime? asOf,
    String? tz = 'Africa/Abidjan',
    DateTime? date,
    DateTime? from,
    DateTime? to,
  }) {
    final r = resolveRevenuePeriod(
      kind: kind,
      compare: compare,
      asOf: asOf ?? DateTime.utc(2026, 11, 25, 14, 30),
      tzName: tz,
      date: date,
      from: from,
      to: to,
    );
    expect(r.error, isNull, reason: 'the request was refused: ${r.error}');
    return r.period!;
  }

  String range(RevenueDayRange? r) => r == null ? 'none' : '$r';

  group('§3.5 — the table, a past period (no like-for-like)', () {
    // 2026-11-25 is a Wednesday; asked about a day in June 2025 so that no
    // period is in progress.
    final june = d(2025, 6, 18); // a Wednesday

    final cases =
        <
          (
            RevenuePeriodKind,
            RevenueCompareMode,
            String current,
            String comparison,
          )
        >[
          (
            RevenuePeriodKind.day,
            RevenueCompareMode.previous,
            '2025-06-18…2025-06-18',
            '2025-06-17…2025-06-17',
          ),
          (
            RevenuePeriodKind.day,
            RevenueCompareMode.year,
            '2025-06-18…2025-06-18',
            '2024-06-18…2024-06-18',
          ),
          (
            RevenuePeriodKind.week,
            RevenueCompareMode.previous,
            '2025-06-16…2025-06-22',
            '2025-06-09…2025-06-15',
          ),
          (
            RevenuePeriodKind.week,
            RevenueCompareMode.year,
            '2025-06-16…2025-06-22',
            // 52 weeks: the same weekdays.
            '2024-06-17…2024-06-23',
          ),
          (
            RevenuePeriodKind.month,
            RevenueCompareMode.previous,
            '2025-06-01…2025-06-30',
            '2025-05-01…2025-05-31',
          ),
          (
            RevenuePeriodKind.month,
            RevenueCompareMode.year,
            '2025-06-01…2025-06-30',
            '2024-06-01…2024-06-30',
          ),
          (
            RevenuePeriodKind.year,
            RevenueCompareMode.previous,
            '2025-01-01…2025-12-31',
            '2024-01-01…2024-12-31',
          ),
          (
            RevenuePeriodKind.year,
            RevenueCompareMode.year,
            '2025-01-01…2025-12-31',
            '2024-01-01…2024-12-31',
          ),
        ];
    for (final (kind, compare, current, comparison) in cases) {
      test('${kind.name} / ${compare.name}', () {
        final p = resolve(kind, compare: compare, date: june);
        expect(range(p.range), current);
        expect(range(p.comparison), comparison);
        expect(p.inProgress, isFalse);
        expect(p.likeForLike, isFalse);
        expect(p.cutoffUtc, isNull);
        expect(
          p.compareEndUtc,
          salonMidnightUtc(addDays(p.comparison!.to, 1), 'Africa/Abidjan'),
          reason: 'a past period is compared whole',
        );
      });
    }

    test('custom / previous: the same number of days, just before', () {
      final p = resolve(
        RevenuePeriodKind.custom,
        from: d(2025, 3, 10),
        to: d(2025, 3, 19),
      );
      expect(range(p.range), '2025-03-10…2025-03-19');
      expect(range(p.comparison), '2025-02-28…2025-03-09');
    });

    test('custom / year: the same dates a year earlier', () {
      final p = resolve(
        RevenuePeriodKind.custom,
        compare: RevenueCompareMode.year,
        from: d(2025, 3, 10),
        to: d(2025, 3, 19),
      );
      expect(range(p.comparison), '2024-03-10…2024-03-19');
    });

    test('none: no comparison at all', () {
      final p = resolve(
        RevenuePeriodKind.month,
        compare: RevenueCompareMode.none,
        date: june,
      );
      expect(p.comparison, isNull);
      expect(p.compareStartUtc, isNull);
      expect(p.compareEndUtc, isNull);
      expect(p.likeForLike, isFalse);
    });
  });

  group('weeks start on Monday, across a year end', () {
    test('Thursday 1 January 2026 is in the week of Monday 29 December', () {
      final p = resolve(RevenuePeriodKind.week, date: d(2026, 1, 1));
      expect(range(p.range), '2025-12-29…2026-01-04');
      expect(range(p.comparison), '2025-12-22…2025-12-28');
    });

    test('a Sunday belongs to the week before it, a Monday starts one', () {
      expect(
        range(resolve(RevenuePeriodKind.week, date: d(2026, 11, 29)).range),
        '2026-11-23…2026-11-29',
      );
      expect(
        range(resolve(RevenuePeriodKind.week, date: d(2026, 11, 30)).range),
        '2026-11-30…2026-12-06',
      );
    });
  });

  group('29 February, both directions', () {
    test('day: 29 Feb 2028 compared with 28 Feb 2027', () {
      final p = resolve(
        RevenuePeriodKind.day,
        compare: RevenueCompareMode.year,
        date: d(2028, 2, 29),
        asOf: DateTime.utc(2028, 6),
      );
      expect(range(p.comparison), '2027-02-28…2027-02-28');
    });

    test('day: 28 Feb 2029 compared with 28 Feb 2028 (not the 29th)', () {
      final p = resolve(
        RevenuePeriodKind.day,
        compare: RevenueCompareMode.year,
        date: d(2029, 2, 28),
        asOf: DateTime.utc(2029, 6),
      );
      expect(range(p.comparison), '2028-02-28…2028-02-28');
    });

    test('month: February 2028 (29 days) against February 2027 (28)', () {
      final p = resolve(
        RevenuePeriodKind.month,
        compare: RevenueCompareMode.year,
        date: d(2028, 2, 10),
        asOf: DateTime.utc(2028, 6),
      );
      expect(range(p.range), '2028-02-01…2028-02-29');
      expect(range(p.comparison), '2027-02-01…2027-02-28');
    });

    test('previous month of March 2028 is February 2028, in full', () {
      final p = resolve(
        RevenuePeriodKind.month,
        date: d(2028, 3, 31),
        asOf: DateTime.utc(2028, 6),
      );
      expect(range(p.comparison), '2028-02-01…2028-02-29');
    });
  });

  group(
    'like for like (Q8): the comparison is cut, never the current range',
    () {
      test('25 November 14:30 — November whole, October to 25 Oct 14:30', () {
        final asOf = DateTime.utc(2026, 11, 25, 14, 30);
        final p = resolve(RevenuePeriodKind.month, asOf: asOf);
        expect(range(p.range), '2026-11-01…2026-11-30');
        expect(p.inProgress, isTrue);
        expect(p.startUtc, DateTime.utc(2026, 11));
        expect(p.endUtc, DateTime.utc(2026, 12), reason: 'never cut at now');
        expect(range(p.comparison), '2026-10-01…2026-10-31');
        expect(p.likeForLike, isTrue);
        expect(p.cutoffUtc, DateTime.utc(2026, 10, 25, 14, 30));
        expect(p.compareStartUtc, DateTime.utc(2026, 10));
        expect(p.compareEndUtc, p.cutoffUtc);
      });

      test('on the 1st: the comparison stops on its own 1st, same time', () {
        final p = resolve(
          RevenuePeriodKind.month,
          asOf: DateTime.utc(2026, 11, 1, 9, 5, 7),
        );
        expect(p.cutoffUtc, DateTime.utc(2026, 10, 1, 9, 5, 7));
      });

      test('on the 15th', () {
        final p = resolve(
          RevenuePeriodKind.month,
          asOf: DateTime.utc(2026, 11, 15, 18),
        );
        expect(p.cutoffUtc, DateTime.utc(2026, 10, 15, 18));
      });

      test('on the last day of a 31-day month against a 30-day one', () {
        final p = resolve(
          RevenuePeriodKind.month,
          asOf: DateTime.utc(2026, 12, 31, 10),
        );
        // Day offset 30 lands on 1 December — past November's end: clipped to
        // November's end (30 Nov 24:00).
        expect(range(p.comparison), '2026-11-01…2026-11-30');
        expect(p.cutoffUtc, DateTime.utc(2026, 12));
      });

      test('31 March is clipped to 28 February 24:00', () {
        final p = resolve(
          RevenuePeriodKind.month,
          asOf: DateTime.utc(2027, 3, 31, 16, 45),
        );
        expect(range(p.comparison), '2027-02-01…2027-02-28');
        expect(p.cutoffUtc, DateTime.utc(2027, 3));
      });

      test(
        'the cutoff is salon wall-clock time, not UTC (Africa/Lagos, +1)',
        () {
          // 13:30 UTC is 14:30 in Lagos.
          final p = resolve(
            RevenuePeriodKind.month,
            asOf: DateTime.utc(2026, 11, 25, 13, 30),
            tz: 'Africa/Lagos',
          );
          expect(p.startUtc, DateTime.utc(2026, 10, 31, 23));
          // 25 October 14:30 in Lagos = 13:30 UTC.
          expect(p.cutoffUtc, DateTime.utc(2026, 10, 25, 13, 30));
        },
      );

      test('a year in progress is compared with the same day of last year', () {
        final p = resolve(
          RevenuePeriodKind.year,
          asOf: DateTime.utc(2026, 11, 25, 14, 30),
        );
        expect(range(p.comparison), '2025-01-01…2025-12-31');
        expect(p.cutoffUtc, DateTime.utc(2025, 11, 25, 14, 30));
      });

      test('a week in progress against 52 weeks earlier', () {
        final p = resolve(
          RevenuePeriodKind.week,
          compare: RevenueCompareMode.year,
          asOf: DateTime.utc(2026, 11, 25, 8),
        );
        expect(range(p.range), '2026-11-23…2026-11-29');
        expect(range(p.comparison), '2025-11-24…2025-11-30');
        expect(p.cutoffUtc, DateTime.utc(2025, 11, 26, 8));
      });

      test('a future period is compared whole', () {
        final p = resolve(RevenuePeriodKind.month, date: d(2027, 1, 10));
        expect(p.inProgress, isFalse);
        expect(p.likeForLike, isFalse);
        expect(p.cutoffUtc, isNull);
      });

      test('compare=none in progress: nothing to cut', () {
        final p = resolve(
          RevenuePeriodKind.month,
          compare: RevenueCompareMode.none,
        );
        expect(p.inProgress, isTrue);
        expect(p.likeForLike, isFalse);
      });
    },
  );

  group('no `date` → the salon\'s today, as the server reads it', () {
    // Lagos is UTC+1: 23:30 UTC on 31 October is already 1 November there.
    test('just after salon midnight', () {
      final p = resolve(
        RevenuePeriodKind.month,
        asOf: DateTime.utc(2026, 10, 31, 23, 30),
        tz: 'Africa/Lagos',
      );
      expect(range(p.range), '2026-11-01…2026-11-30');
      expect(p.today, d(2026, 11, 1));
    });

    test('just before salon midnight', () {
      final p = resolve(
        RevenuePeriodKind.month,
        asOf: DateTime.utc(2026, 10, 31, 22, 30),
        tz: 'Africa/Lagos',
      );
      expect(range(p.range), '2026-10-01…2026-10-31');
    });

    test('an unknown zone reads as Abidjan', () {
      final p = resolve(RevenuePeriodKind.day, tz: null);
      expect(p.timezone, 'Africa/Abidjan');
      expect(range(p.range), '2026-11-25…2026-11-25');
    });
  });

  group('bounds', () {
    RevenuePeriodResult raw({
      RevenuePeriodKind kind = RevenuePeriodKind.custom,
      DateTime? date,
      DateTime? from,
      DateTime? to,
    }) => resolveRevenuePeriod(
      kind: kind,
      compare: RevenueCompareMode.previous,
      asOf: DateTime.utc(2026, 11, 25, 14, 30),
      tzName: 'Africa/Abidjan',
      date: date,
      from: from,
      to: to,
    );

    test('366 days, both ends counted, is the longest custom range', () {
      expect(raw(from: d(2025, 1, 1), to: d(2026, 1, 1)).error, isNull);
      expect(
        raw(from: d(2025, 1, 1), to: d(2026, 1, 2)).error,
        'range_too_long',
      );
    });

    test('nothing before 2020-01-01', () {
      expect(raw(from: d(2020, 1, 1), to: d(2020, 1, 31)).error, isNull);
      expect(
        raw(from: d(2019, 12, 31), to: d(2020, 1, 31)).error,
        'invalid_input',
      );
      expect(
        raw(kind: RevenuePeriodKind.day, date: d(2019, 12, 31)).error,
        'invalid_input',
      );
    });

    test('nothing after the salon\'s today + 366 days', () {
      // today = 2026-11-25 → latest 2027-11-26.
      expect(
        raw(kind: RevenuePeriodKind.day, date: d(2027, 11, 26)).error,
        isNull,
      );
      expect(
        raw(kind: RevenuePeriodKind.day, date: d(2027, 11, 27)).error,
        'invalid_input',
      );
      expect(
        raw(from: d(2027, 1, 1), to: d(2027, 11, 27)).error,
        'invalid_input',
      );
    });

    test('from after to', () {
      expect(
        raw(from: d(2026, 3, 2), to: d(2026, 3, 1)).error,
        'invalid_input',
      );
    });

    test('custom needs from and to, and no date; the others no from/to', () {
      expect(raw(from: d(2026, 3, 1)).error, 'invalid_input');
      expect(
        raw(from: d(2026, 3, 1), to: d(2026, 3, 2), date: d(2026, 3, 1)).error,
        'invalid_input',
      );
      expect(
        raw(kind: RevenuePeriodKind.month, from: d(2026, 3, 1)).error,
        'invalid_input',
      );
    });

    test('a future period inside the bound is allowed', () {
      expect(
        raw(kind: RevenuePeriodKind.month, date: d(2027, 6, 1)).error,
        isNull,
      );
    });
  });

  group('the chart\'s buckets', () {
    test('a month: one bucket a day', () {
      final p = resolve(RevenuePeriodKind.month, date: d(2025, 6, 1));
      expect(p.bucketUnit, RevenueBucketUnit.day);
      expect(p.buckets, hasLength(30));
      expect(p.bucketIndexOf(d(2025, 6, 30)), 29);
      expect(p.bucketIndexOf(d(2025, 7, 1)), -1);
    });

    test('31 days → day; 32 days → Monday weeks, clipped to the range', () {
      expect(
        resolve(
          RevenuePeriodKind.custom,
          from: d(2025, 1, 1),
          to: d(2025, 1, 31),
        ).bucketUnit,
        RevenueBucketUnit.day,
      );
      final p = resolve(
        RevenuePeriodKind.custom,
        from: d(2025, 1, 1), // a Wednesday
        to: d(2025, 2, 1),
      );
      expect(p.bucketUnit, RevenueBucketUnit.week);
      expect(p.buckets.first.toString(), '2025-01-01…2025-01-05');
      expect(p.buckets[1].toString(), '2025-01-06…2025-01-12');
      expect(p.buckets.last.toString(), '2025-01-27…2025-02-01');
    });

    test('92 days → weeks; 93 → months, clipped', () {
      expect(
        resolve(
          RevenuePeriodKind.custom,
          from: d(2025, 1, 1),
          to: d(2025, 4, 2),
        ).bucketUnit,
        RevenueBucketUnit.week,
      );
      final p = resolve(
        RevenuePeriodKind.custom,
        from: d(2025, 1, 15),
        to: d(2025, 4, 17),
      );
      expect(p.bucketUnit, RevenueBucketUnit.month);
      expect(p.buckets.map((b) => '$b'), [
        '2025-01-15…2025-01-31',
        '2025-02-01…2025-02-28',
        '2025-03-01…2025-03-31',
        '2025-04-01…2025-04-17',
      ]);
    });

    test('a year: twelve months; a day: one bucket', () {
      expect(
        resolve(RevenuePeriodKind.year, date: d(2025, 1, 1)).buckets,
        hasLength(12),
      );
      expect(
        resolve(RevenuePeriodKind.day, date: d(2025, 1, 1)).buckets,
        hasLength(1),
      );
    });

    test('the buckets cover the range, contiguous, in order', () {
      for (final kind in [
        RevenuePeriodKind.week,
        RevenuePeriodKind.month,
        RevenuePeriodKind.year,
      ]) {
        final p = resolve(kind, date: d(2024, 2, 29));
        expect(p.buckets.first.from, p.range.from);
        expect(p.buckets.last.to, p.range.to);
        for (var i = 1; i < p.buckets.length; i++) {
          expect(p.buckets[i].from, addDays(p.buckets[i - 1].to, 1));
        }
      }
    });
  });
}

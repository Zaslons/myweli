import 'package:timezone/timezone.dart' as tz;

import '../salon_time.dart';

// The calendar of the revenue analytics — which days a period covers, what it
// is compared with, and where the comparison stops while the period is still
// running. Pure: no clock, no I/O; « now » is the caller's `asOf`.
//
// Design: docs/design/pro-revenue-analytics.md §3.5 (decision 244).
//
// **Dates are salon calendar days**, held as UTC-midnight `DateTime`s so that
// arithmetic on them is date arithmetic (`DateTime.utc(y, m, d + n)`), with no
// clock and no DST anywhere near them. Instants (`*Utc`) are only made at the
// edges, through the salon's timezone.

/// The periods a salon can ask for.
enum RevenuePeriodKind { day, week, month, year, custom }

/// What the period is compared with.
enum RevenueCompareMode { previous, year, none }

/// The unit of the chart's series.
enum RevenueBucketUnit { day, week, month }

/// No range starts before this day (§3.5's bounds).
final DateTime kRevenueEarliestDate = DateTime.utc(2020);

/// The longest range, in days, counting both ends — and how far past the
/// salon's today a date may be.
const int kRevenueMaxDays = 366;

/// A salon calendar day from its fields.
DateTime revenueDate(int year, int month, int day) =>
    DateTime.utc(year, month, day);

/// `YYYY-MM-DD` of a salon calendar day.
String revenueDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// [d] plus [days] calendar days.
DateTime addDays(DateTime d, int days) =>
    DateTime.utc(d.year, d.month, d.day + days);

/// The number of calendar days from [a] to [b] (b − a).
int daysBetween(DateTime a, DateTime b) => b.difference(a).inDays;

DateTime _lastOfMonth(int year, int month) => DateTime.utc(year, month + 1, 0);

/// The same date a year earlier; 29 February becomes 28 February.
DateTime yearEarlier(DateTime d) {
  final last = _lastOfMonth(d.year - 1, d.month).day;
  return DateTime.utc(d.year - 1, d.month, d.day > last ? last : d.day);
}

/// An inclusive range of salon calendar days.
class RevenueDayRange {
  const RevenueDayRange(this.from, this.to);

  final DateTime from;
  final DateTime to;

  /// Its length, both ends counted.
  int get days => daysBetween(from, to) + 1;

  bool contains(DateTime d) => !d.isBefore(from) && !d.isAfter(to);

  @override
  String toString() => '${revenueDateKey(from)}…${revenueDateKey(to)}';
}

/// What [resolveRevenuePeriod] answers: everything the aggregator and the
/// response need about the calendar.
class ResolvedRevenuePeriod {
  const ResolvedRevenuePeriod({
    required this.kind,
    required this.range,
    required this.today,
    required this.asOf,
    required this.timezone,
    required this.inProgress,
    required this.startUtc,
    required this.endUtc,
    required this.compareMode,
    required this.comparison,
    required this.likeForLike,
    required this.cutoffUtc,
    required this.compareStartUtc,
    required this.compareEndUtc,
    required this.bucketUnit,
    required this.buckets,
  });

  final RevenuePeriodKind kind;

  /// The current period's days.
  final RevenueDayRange range;

  /// The salon's today at [asOf].
  final DateTime today;

  /// The server's « now » for this answer (UTC).
  final DateTime asOf;

  /// The salon's IANA zone, as resolved (absent → Abidjan).
  final String timezone;

  /// [today] is inside [range].
  final bool inProgress;

  /// The current range as instants: `[startUtc, endUtc)`. Never cut — the
  /// current period is always counted whole (§3.2).
  final DateTime startUtc;
  final DateTime endUtc;

  final RevenueCompareMode compareMode;

  /// The comparison's days, or null with [RevenueCompareMode.none].
  final RevenueDayRange? comparison;

  /// The comparison stops at the same point of its own period ([cutoffUtc]).
  final bool likeForLike;

  /// Where the comparison stops when [likeForLike]; else null.
  final DateTime? cutoffUtc;

  /// The comparison as instants: `[compareStartUtc, compareEndUtc)`, the end
  /// being [cutoffUtc] when [likeForLike]. Null without a comparison.
  final DateTime? compareStartUtc;
  final DateTime? compareEndUtc;

  final RevenueBucketUnit bucketUnit;

  /// The chart's buckets over [range], in order, contiguous, clipped to it.
  final List<RevenueDayRange> buckets;

  /// The index of the bucket holding [day] (a day inside [range]), or -1.
  int bucketIndexOf(DateTime day) {
    switch (bucketUnit) {
      case RevenueBucketUnit.day:
        final i = daysBetween(range.from, day);
        return (i >= 0 && i < buckets.length) ? i : -1;
      case RevenueBucketUnit.week:
      case RevenueBucketUnit.month:
        for (var i = 0; i < buckets.length; i++) {
          if (buckets[i].contains(day)) return i;
        }
        return -1;
    }
  }
}

/// The outcome of [resolveRevenuePeriod]: a period, or the machine code of
/// the 400 (`invalid_input`, `range_too_long`).
typedef RevenuePeriodResult = ({ResolvedRevenuePeriod? period, String? error});

/// The salon calendar day of an instant.
DateTime salonDateOf(DateTime instant, String? tzName) {
  final w = salonWallClock(instant, tzName);
  return DateTime.utc(w.year, w.month, w.day);
}

/// The instant a salon calendar day starts.
DateTime salonMidnightUtc(DateTime day, String? tzName) =>
    salonCalendarDayBoundsUtc(day, tzName).startUtc;

/// Resolves a period request (§3.5).
///
/// - [date] is any day inside the period, absent → the salon's today at
///   [asOf] (so a phone whose clock is wrong still opens on the right month);
///   not with `custom`, which takes [from] and [to] instead.
/// - Bounds: every date sent is on or after 2020-01-01 and no later than the
///   salon's today + 366 days; a `custom` range is at most 366 days, both
///   ends counted (`range_too_long`).
/// - **Like for like:** while the salon's today is inside the current range,
///   the comparison is cut at the same day offset from its own start and the
///   same salon wall-clock time as [asOf]; a cut past the comparison's own
///   end is clipped to it (31 March → 28 February 24:00).
RevenuePeriodResult resolveRevenuePeriod({
  required RevenuePeriodKind kind,
  required RevenueCompareMode compare,
  required DateTime asOf,
  required String? tzName,
  DateTime? date,
  DateTime? from,
  DateTime? to,
}) {
  const bad = (period: null, error: 'invalid_input');
  final now = asOf.toUtc();
  final today = salonDateOf(now, tzName);
  final latest = addDays(today, kRevenueMaxDays);
  bool inBounds(DateTime d) =>
      !d.isBefore(kRevenueEarliestDate) && !d.isAfter(latest);

  final RevenueDayRange range;
  if (kind == RevenuePeriodKind.custom) {
    if (date != null || from == null || to == null) return bad;
    if (!inBounds(from) || !inBounds(to) || to.isBefore(from)) return bad;
    range = RevenueDayRange(from, to);
    if (range.days > kRevenueMaxDays) {
      return (period: null, error: 'range_too_long');
    }
  } else {
    if (from != null || to != null) return bad;
    final d = date ?? today;
    if (!inBounds(d)) return bad;
    range = _rangeOf(kind, d);
  }

  final comparison = switch (compare) {
    RevenueCompareMode.none => null,
    RevenueCompareMode.previous => _previousOf(kind, range),
    RevenueCompareMode.year => _yearBeforeOf(kind, range),
  };

  final inProgress = range.contains(today);
  final location = locationOf(tzName);
  final startUtc = salonMidnightUtc(range.from, tzName);
  final endUtc = salonMidnightUtc(addDays(range.to, 1), tzName);

  DateTime? compareStartUtc;
  DateTime? compareEndUtc;
  DateTime? cutoffUtc;
  var likeForLike = false;
  if (comparison != null) {
    compareStartUtc = salonMidnightUtc(comparison.from, tzName);
    final fullEnd = salonMidnightUtc(addDays(comparison.to, 1), tzName);
    compareEndUtc = fullEnd;
    if (inProgress) {
      likeForLike = true;
      final cutDay = addDays(comparison.from, daysBetween(range.from, today));
      if (cutDay.isAfter(comparison.to)) {
        cutoffUtc = fullEnd;
      } else {
        final wall = tz.TZDateTime.from(now, location);
        cutoffUtc = tz.TZDateTime(
          location,
          cutDay.year,
          cutDay.month,
          cutDay.day,
          wall.hour,
          wall.minute,
          wall.second,
          wall.millisecond,
          wall.microsecond,
        ).toUtc();
      }
      compareEndUtc = cutoffUtc;
    }
  }

  final unit = range.days <= 31
      ? RevenueBucketUnit.day
      : range.days <= 92
      ? RevenueBucketUnit.week
      : RevenueBucketUnit.month;

  return (
    period: ResolvedRevenuePeriod(
      kind: kind,
      range: range,
      today: today,
      asOf: now,
      timezone: tzName ?? kDefaultSalonTz,
      inProgress: inProgress,
      startUtc: startUtc,
      endUtc: endUtc,
      compareMode: compare,
      comparison: comparison,
      likeForLike: likeForLike,
      cutoffUtc: cutoffUtc,
      compareStartUtc: compareStartUtc,
      compareEndUtc: compareEndUtc,
      bucketUnit: unit,
      buckets: _bucketsOf(unit, range),
    ),
    error: null,
  );
}

RevenueDayRange _rangeOf(RevenuePeriodKind kind, DateTime d) {
  switch (kind) {
    case RevenuePeriodKind.day:
      return RevenueDayRange(d, d);
    case RevenuePeriodKind.week:
      final monday = addDays(d, -(d.weekday - DateTime.monday));
      return RevenueDayRange(monday, addDays(monday, 6));
    case RevenuePeriodKind.month:
      return RevenueDayRange(
        DateTime.utc(d.year, d.month),
        _lastOfMonth(d.year, d.month),
      );
    case RevenuePeriodKind.year:
      return RevenueDayRange(
        DateTime.utc(d.year),
        DateTime.utc(d.year, 12, 31),
      );
    case RevenuePeriodKind.custom:
      throw ArgumentError.value(kind, 'kind', 'custom has no date range');
  }
}

RevenueDayRange _previousOf(RevenuePeriodKind kind, RevenueDayRange r) {
  switch (kind) {
    case RevenuePeriodKind.day:
      return RevenueDayRange(addDays(r.from, -1), addDays(r.to, -1));
    case RevenuePeriodKind.week:
      return RevenueDayRange(addDays(r.from, -7), addDays(r.to, -7));
    case RevenuePeriodKind.month:
      final start = DateTime.utc(r.from.year, r.from.month - 1);
      return RevenueDayRange(start, _lastOfMonth(start.year, start.month));
    case RevenuePeriodKind.year:
      return RevenueDayRange(
        DateTime.utc(r.from.year - 1),
        DateTime.utc(r.from.year - 1, 12, 31),
      );
    case RevenuePeriodKind.custom:
      return RevenueDayRange(addDays(r.from, -r.days), addDays(r.from, -1));
  }
}

RevenueDayRange _yearBeforeOf(RevenuePeriodKind kind, RevenueDayRange r) {
  switch (kind) {
    case RevenuePeriodKind.day:
    case RevenuePeriodKind.custom:
      return RevenueDayRange(yearEarlier(r.from), yearEarlier(r.to));
    case RevenuePeriodKind.week:
      // 52 weeks: the same weekdays, a year (364 days) earlier.
      return RevenueDayRange(addDays(r.from, -364), addDays(r.to, -364));
    case RevenuePeriodKind.month:
      return RevenueDayRange(
        DateTime.utc(r.from.year - 1, r.from.month),
        _lastOfMonth(r.from.year - 1, r.from.month),
      );
    case RevenuePeriodKind.year:
      return _previousOf(kind, r);
  }
}

List<RevenueDayRange> _bucketsOf(RevenueBucketUnit unit, RevenueDayRange r) {
  final out = <RevenueDayRange>[];
  var start = r.from;
  while (!start.isAfter(r.to)) {
    final DateTime natural = switch (unit) {
      RevenueBucketUnit.day => start,
      RevenueBucketUnit.week => addDays(start, DateTime.sunday - start.weekday),
      RevenueBucketUnit.month => _lastOfMonth(start.year, start.month),
    };
    final end = natural.isAfter(r.to) ? r.to : natural;
    out.add(RevenueDayRange(start, end));
    start = addDays(end, 1);
  }
  return out;
}

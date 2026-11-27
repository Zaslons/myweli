import '../../models/revenue_analytics.dart';
import 'formatters.dart';
import 'salon_time.dart';

/// The period bar's calendar (docs/design/pro-revenue-analytics.md §3.5,
/// §4.3) — pure, so every rule has a unit test.
///
/// **The server owns the calendar**: the app never resolves a week or a
/// month. It only steps from the server's answer — « ‹ › sends the `date` the
/// client computes from the answer's `from` (one unit earlier or later): date
/// arithmetic on a date, no clock involved ». The one « today » it needs (how
/// far › may go) is the answer's own `asOf` read in the salon's zone, never
/// the phone's clock.

/// The salon's today, as the answer measured it.
DateTime revenueToday(RevenueAnalytics a) =>
    salonToday(now: a.asOf, tz: a.timezone);

/// The last day the server accepts: the salon's today + 366 days.
DateTime revenueLatestDay(RevenueAnalytics a) =>
    addRevenueDays(revenueToday(a), kRevenueMaxDays);

/// The period before [a]'s, as a query — or null at 2020 (« ‹ stops at
/// 2020 »). A period that straddles 1 January 2020 is asked by its first
/// valid day: the week of 1 January 2020 starts on 30 December 2019, and the
/// server accepts the period around a valid date (§20.1 item 1).
RevenueQuery? previousRevenuePeriod(RevenueAnalytics a, RevenueQuery q) {
  final DateTime from;
  final DateTime to;
  switch (a.period) {
    case RevenuePeriod.day:
      from = addRevenueDays(a.from, -1);
      to = from;
    case RevenuePeriod.week:
      from = addRevenueDays(a.from, -7);
      to = addRevenueDays(a.from, -1);
    case RevenuePeriod.month:
      from = revenueDay(a.from.year, a.from.month - 1, 1);
      to = addRevenueDays(a.from, -1);
    case RevenuePeriod.year:
      from = revenueDay(a.from.year - 1, 1, 1);
      to = addRevenueDays(a.from, -1);
    case RevenuePeriod.custom:
      // « custom ranges step by their own length »; both ends must be valid.
      from = addRevenueDays(a.from, -a.days);
      to = addRevenueDays(a.from, -1);
      if (from.isBefore(kRevenueEarliestDay)) return null;
      return q.withPeriod(period: RevenuePeriod.custom, from: from, to: to);
  }
  if (to.isBefore(kRevenueEarliestDay)) return null;
  return q.withPeriod(
    period: a.period,
    date: from.isBefore(kRevenueEarliestDay) ? kRevenueEarliestDay : from,
  );
}

/// The period after [a]'s, as a query — or null past the salon's today +
/// 366 days (« › stops at today + 366 days »).
RevenueQuery? nextRevenuePeriod(RevenueAnalytics a, RevenueQuery q) {
  final latest = revenueLatestDay(a);
  final next = addRevenueDays(a.to, 1);
  if (a.period == RevenuePeriod.custom) {
    final to = addRevenueDays(a.to, a.days);
    if (to.isAfter(latest)) return null;
    return q.withPeriod(period: RevenuePeriod.custom, from: next, to: to);
  }
  if (next.isAfter(latest)) return null;
  return q.withPeriod(period: a.period, date: next);
}

/// Another kind of period, keeping the anchor (§4.3): the current one when
/// [a] contains today (no date — the server's today), else [a]'s first day.
/// From « Mois » (novembre 2026, in progress) to « Semaine »: this week; from
/// a past month: that month's first week.
RevenueQuery switchRevenuePeriod(
  RevenueAnalytics? a,
  RevenueQuery q,
  RevenuePeriod period,
) {
  assert(period != RevenuePeriod.custom, 'custom opens its own sheet');
  final anchor = (a == null || a.inProgress) ? null : a.from;
  return q.withPeriod(period: period, date: anchor);
}

/// Why a « Dates… » range is refused — the error under « Au » (§4.3), or
/// null when it can be asked.
String? customRangeError(DateTime from, DateTime to) {
  if (to.isBefore(from)) return 'La date de fin précède la date de début';
  if (revenueDaysBetween(from, to) + 1 > kRevenueMaxDays) {
    return '366 jours au plus';
  }
  return null;
}

/// The period's title (§4.3): « Mardi 25 novembre » · « 24 – 30 nov. 2026 »
/// · « Novembre 2026 » · « 2026 » · « 3 oct. – 25 nov. 2026 ».
String revenuePeriodTitle(RevenueAnalytics a) => switch (a.period) {
  RevenuePeriod.day => Formatters.formatPeriodDay(
    a.from,
    currentYear: revenueToday(a).year,
  ),
  RevenuePeriod.month => Formatters.capitalized(
    Formatters.formatMonthYear(a.from),
  ),
  RevenuePeriod.year => '${a.from.year}',
  RevenuePeriod.week ||
  RevenuePeriod.custom => Formatters.formatDayRange(a.from, a.to),
};

/// What the period is compared with, in words — « octobre 2026 »,
/// « 1er – 25 oct. 2026, même avancement », « 2025 » — or null with
/// « Aucune comparaison ». The same words end a delta's spoken sentence
/// (« en hausse de 12 % par rapport à octobre 2026 », §12.3).
String? revenueComparisonLabel(RevenueAnalytics a) {
  final c = a.comparison;
  final from = c.from;
  final to = c.to;
  if (c.mode == RevenueCompare.none || from == null || to == null) {
    return null;
  }
  if (c.likeForLike && c.cutoff != null) {
    // The last day the cut reaches: the day of the instant just before it
    // (a cut clipped to its period's end is midnight after `to`).
    final last = salonToday(
      now: c.cutoff!.subtract(const Duration(microseconds: 1)),
      tz: a.timezone,
    );
    final end = last.isBefore(from) ? from : (last.isAfter(to) ? to : last);
    return '${Formatters.formatDayRange(from, end)}, même avancement';
  }
  final wholeMonth =
      from.day == 1 && addRevenueDays(to, 1).day == 1 && from.month == to.month;
  if (wholeMonth) return Formatters.formatMonthYear(from);
  final wholeYear =
      from.month == 1 && from.day == 1 && to.month == 12 && to.day == 31;
  if (wholeYear && from.year == to.year) return '${from.year}';
  return Formatters.formatDayRange(from, to);
}

/// The period has days today or later — « Prévu » is shown (§4.5).
bool revenueHasFuture(RevenueAnalytics a) => !a.to.isBefore(revenueToday(a));

/// The period has not begun (§4.11 « A future period »).
bool revenueIsFuture(RevenueAnalytics a) => a.from.isAfter(revenueToday(a));

/// The title of [q] before its answer lands, so the bar updates at once
/// (§4.11 « Period change ») — the same words as [revenuePeriodTitle], from
/// the query's own dates: the day, its month, its year, the Monday of its
/// week (§3.5's rule), or the custom range. The answer's dates replace it.
/// [today] is the salon's today from the last answer, for a query with no
/// date; null when no answer has said it yet.
String? provisionalRevenueTitle(RevenueQuery q, {DateTime? today}) {
  if (q.period == RevenuePeriod.custom) {
    return Formatters.formatDayRange(q.from!, q.to!);
  }
  final d = q.date ?? today;
  if (d == null) return null;
  return switch (q.period) {
    RevenuePeriod.day => Formatters.formatPeriodDay(
      d,
      currentYear: (today ?? d).year,
    ),
    RevenuePeriod.week => () {
      final monday = addRevenueDays(d, -(d.weekday - DateTime.monday));
      return Formatters.formatDayRange(monday, addRevenueDays(monday, 6));
    }(),
    RevenuePeriod.month => Formatters.capitalized(
      Formatters.formatMonthYear(revenueDay(d.year, d.month, 1)),
    ),
    RevenuePeriod.year => '${d.year}',
    RevenuePeriod.custom => null,
  };
}

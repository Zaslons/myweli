import '../../widgets/common/myweli_month_grid.dart' show CalendarDay;
import 'salon_time.dart';

/// The one place a blocked-date write is composed (A14e).
///
/// **The trap it exists for, and why it takes a DELTA rather than a set.** The
/// multi-picker's `firstDate` is the salon's today, so `MyweliMonthGrid._enabled`
/// refuses every earlier day — a past blocked date **cannot** be in the
/// picker's selection, and seeding one would paint it selected and inert. A
/// page that wrote `copyWith(blockedDates: picked.map(...).toList())` would
/// therefore delete every blocked date before today, on the first save, with
/// no error, and irrecoverably: the server replaces the whole set with a
/// `DELETE` and re-insert.
///
/// Taking a delta means the days this write must not touch are never in scope
/// at all. Erasure stops being something to remember and becomes something the
/// shape cannot express — which matters because the property is invisible from
/// the UI: past days never render in the picker, so nobody would see them go.
///
/// It is a top-level function rather than a method on the screen so it has a
/// test subject that is not a widget pump. §16 records what the alternative
/// costs: *"the grid's own contract had no subject, which is how §16's three
/// defects survived being read past twice."*
List<DateTime> applyBlockedDaysDelta({
  required List<DateTime> current,
  required Set<CalendarDay> added,
  required Set<CalendarDay> removed,
  required String? tz,
}) {
  // Survivors keep their ORIGINAL stored instant. Not re-derived through
  // `salonDateTime`: a day this write is not changing must not be silently
  // rewritten into a flavour it did not arrive in — web writes these too, and
  // the stored value is a salon-midnight instant whichever side made it.
  //
  // Matching goes through `CalendarDay.of(toSalonTime(...))`, never
  // `Set<DateTime>.contains`: `blockedDates` is a `List<DateTime>` and
  // `DateTime.==` compares microseconds AND `isUtc`, so a set would silently
  // match nothing across the three flavours this list can hold.
  final kept = [
    for (final d in current)
      if (!removed.contains(CalendarDay.of(toSalonTime(d, tz: tz)))) d,
  ];

  // §18: only the call site knows the salon's zone, so a NEW day becomes an
  // instant here and nowhere else. `CalendarDay.toDateTime()` is deliberately
  // not used — its own docstring says it is "never what a caller persists",
  // because it composes a device-local value.
  final fresh = [
    for (final d in added) salonDateTime(d.year, d.month, d.day, tz: tz),
  ];

  // Chronological rather than insertion order, which is what the cards
  // rendered before: a date blocked today sat above one blocked for next week.
  return [...kept, ...fresh]..sort();
}

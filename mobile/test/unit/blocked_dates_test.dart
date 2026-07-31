import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/blocked_dates.dart';
import 'package:myweli/core/utils/salon_time.dart';
import 'package:myweli/widgets/common/myweli_month_grid.dart';

/// A14e — composing a blocked-date write from a multi-select.
///
/// **The trap this file exists for, and it is silent and permanent.** The
/// multi-picker's `firstDate` is the salon's today, so `MyweliMonthGrid._enabled`
/// refuses every earlier day: a past blocked date **cannot** be in the picker's
/// selection, and seeding one would paint it selected-and-dead. A page that
/// wrote `copyWith(blockedDates: picked.map(...).toList())` would therefore
/// delete every blocked date before today — on the first save, with no error,
/// and irrecoverably, because the server replaces the whole set with a
/// `DELETE` and re-insert.
///
/// So the picker returns a **delta**, and this function never sees the days it
/// must not touch. Erasure stops being something to remember and becomes
/// something the shape cannot express.
void main() {
  const tz = 'Africa/Abidjan';

  DateTime salonDay(int daysFromToday) {
    final t = salonToday(tz: tz);
    return salonDateTime(t.year, t.month, t.day + daysFromToday, tz: tz);
  }

  CalendarDay dayOf(int daysFromToday) =>
      CalendarDay.of(toSalonTime(salonDay(daysFromToday), tz: tz));

  group('a day the picker never showed cannot be erased', () {
    test('a PAST blocked date survives a save that adds two future ones', () {
      final past = salonDay(-30);
      final current = [past, salonDay(3)];

      final out = applyBlockedDaysDelta(
        current: current,
        added: {dayOf(5), dayOf(6)},
        removed: const {},
        tz: tz,
      );

      expect(
        out,
        contains(past),
        reason:
            'the picker cannot select day -30, so it is in neither added nor '
            'removed — a full-set write would drop it silently and for good',
      );
      expect(out, hasLength(4));
    });

    test('an empty delta changes nothing at all', () {
      final current = [salonDay(-10), salonDay(2)];
      expect(
        applyBlockedDaysDelta(
          current: current,
          added: const {},
          removed: const {},
          tz: tz,
        ),
        current,
      );
    });
  });

  group('the delta does what it says', () {
    test('a removed day really is removed', () {
      // The pair matters: without this, `applyBlockedDaysDelta` could ignore
      // `removed` entirely and the erasure test above would still pass.
      final keep = salonDay(2);
      final drop = salonDay(4);

      final out = applyBlockedDaysDelta(
        current: [keep, drop],
        added: const {},
        removed: {dayOf(4)},
        tz: tz,
      );

      expect(out, [keep]);
    });

    test('an added day becomes a salon-midnight instant', () {
      final out = applyBlockedDaysDelta(
        current: const [],
        added: {dayOf(7)},
        removed: const {},
        tz: tz,
      );
      expect(out, hasLength(1));
      // §18: only the call site knows the zone, so a NEW day becomes an
      // instant here and nowhere else.
      expect(toSalonTime(out.single, tz: tz).day, dayOf(7).day);
    });

    test('the result is chronological', () {
      // A free fix: the cards render in stored order, which was insertion
      // order — a date blocked today sat above one blocked for next week.
      final out = applyBlockedDaysDelta(
        current: [salonDay(9), salonDay(1)],
        added: {dayOf(5)},
        removed: const {},
        tz: tz,
      );
      expect(out, [salonDay(1), salonDay(5), salonDay(9)]);
    });
  });

  group('mixed DateTime flavours classify to the same salon day', () {
    test('a local, a UTC and a TZDateTime all match', () {
      // `blockedDates` is a `List<DateTime>` and `DateTime.==` compares
      // microseconds AND `isUtc`, so a `Set<DateTime>` matches none of these
      // against each other. `CalendarDay.of(toSalonTime(...))` reads only
      // y/m/d, which is what makes it safe — and is why this file never builds
      // a `Set<DateTime>` at any point.
      final t = salonToday(tz: tz);
      final asUtc = DateTime.utc(t.year, t.month, t.day + 3);
      final asLocal = DateTime(t.year, t.month, t.day + 3);

      for (final flavour in [asUtc, asLocal]) {
        final out = applyBlockedDaysDelta(
          current: [flavour],
          added: const {},
          removed: {dayOf(3)},
          tz: tz,
        );
        expect(
          out,
          isEmpty,
          reason: 'removing day +3 must match a $flavour written by anyone',
        );
      }
    });
  });
}

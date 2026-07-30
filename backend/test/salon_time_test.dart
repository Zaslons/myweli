import 'package:myweli_backend/src/salon_time.dart';
import 'package:test/test.dart';

/// The backend salon-time seam (multi-pays MP1 —
/// docs/design/multi-pays-end-version.md §3). Africa/Abidjan ≡ UTC proves
/// Wave-0 salons stay bit-identical; Africa/Libreville (UTC+1, no DST) plays
/// the non-zero offset. `locationOf` lazily loads tzdata, so no setup needed.
void main() {
  const abidjan = 'Africa/Abidjan';
  const libreville = 'Africa/Libreville';

  group('locationOf', () {
    test('null and unknown names fall back to Abidjan', () {
      expect(locationOf(null).name, abidjan);
      expect(locationOf('Not/AZone').name, abidjan);
      expect(locationOf(libreville).name, libreville);
    });
  });

  group('sameSalonDay', () {
    final lateNight = DateTime.utc(2026, 7, 13, 23, 30);
    final nextMorning = DateTime.utc(2026, 7, 14, 0, 10);

    test('Abidjan rolls at UTC midnight', () {
      expect(sameSalonDay(lateNight, nextMorning, abidjan), isFalse);
      expect(
        sameSalonDay(lateNight, DateTime.utc(2026, 7, 13, 0, 10), abidjan),
        isTrue,
      );
    });

    test('Libreville rolls one hour earlier — 23:30Z is already tomorrow', () {
      // 23:30Z = 00:30 Libreville on the 14th; 00:10Z 14th = 01:10 the 14th.
      expect(sameSalonDay(lateNight, nextMorning, libreville), isTrue);
      expect(
        sameSalonDay(lateNight, DateTime.utc(2026, 7, 13, 12), libreville),
        isFalse,
      );
    });
  });

  group('salonDayKey / salonDayBoundsUtc', () {
    test('the day key follows the salon wall-clock', () {
      final t = DateTime.utc(2026, 7, 13, 23, 30);
      expect(salonDayKey(t, abidjan), '2026-07-13');
      expect(salonDayKey(t, libreville), '2026-07-14');
    });

    test('bounds are the salon midnights as UTC instants', () {
      final t = DateTime.utc(2026, 7, 13, 12);
      final ab = salonDayBoundsUtc(t, abidjan);
      expect(ab.startUtc, DateTime.utc(2026, 7, 13));
      expect(ab.endUtc, DateTime.utc(2026, 7, 14));
      final lb = salonDayBoundsUtc(t, libreville);
      expect(lb.startUtc, DateTime.utc(2026, 7, 12, 23));
      expect(lb.endUtc, DateTime.utc(2026, 7, 13, 23));
    });

    test('calendar-day bounds read y/m/d fields as the salon day', () {
      final named = DateTime.utc(2026, 7, 13);
      final lb = salonCalendarDayBoundsUtc(named, libreville);
      expect(lb.startUtc, DateTime.utc(2026, 7, 12, 23)); // 00:00 Libreville
      expect(lb.endUtc, DateTime.utc(2026, 7, 13, 23));
    });
  });

  group('salonWallClockToUtc / salonWallClock', () {
    test('a 09:00 wall-clock is 09:00Z in Abidjan, 08:00Z in Libreville', () {
      expect(
        salonWallClockToUtc(2026, 7, 13, 9 * 60, abidjan),
        DateTime.utc(2026, 7, 13, 9),
      );
      expect(
        salonWallClockToUtc(2026, 7, 13, 9 * 60, libreville),
        DateTime.utc(2026, 7, 13, 8),
      );
    });

    test('salonWallClock renders the salon clock face of an instant', () {
      final wall = salonWallClock(DateTime.utc(2026, 7, 13, 9), libreville);
      expect(wall.hour, 10);
      expect(wall.day, 13);
    });
  });
}

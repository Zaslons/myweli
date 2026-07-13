import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/salon_time.dart';

/// The salon-time seam, per-salon edition (multi-pays MP2 —
/// docs/design/multi-pays-end-version.md §3). Probes are explicit instants —
/// never the process clock — so the suite is meaningful on any machine
/// timezone. Africa/Abidjan (≡ UTC, the default) pins Wave-0 behavior;
/// Africa/Libreville (UTC+1, a LINK zone — the latest_all requirement) plays
/// Wave 2/3.
void main() {
  const lbv = 'Africa/Libreville';

  group('locationOf', () {
    test('null/unknown fall back to Abidjan; LINK zones resolve', () {
      expect(locationOf(null).name, kSalonTz);
      expect(locationOf('Not/AZone').name, kSalonTz);
      // A link zone — proof the bundled dataset keeps links (latest_all).
      expect(locationOf(lbv).name, lbv);
    });
  });

  group('isSameSalonDay', () {
    final lateNight = DateTime.utc(2026, 7, 13, 23, 50);
    final justAfter = DateTime.utc(2026, 7, 14, 0, 10);
    final earlySame = DateTime.utc(2026, 7, 13, 0, 10);

    test('default (Abidjan ≡ UTC): rolls at UTC midnight', () {
      expect(isSameSalonDay(lateNight, justAfter), isFalse);
      expect(isSameSalonDay(lateNight, earlySame), isTrue);
    });

    test('Libreville rolls one hour earlier — 23:50Z is already tomorrow', () {
      expect(isSameSalonDay(lateNight, justAfter, tz: lbv), isTrue);
      expect(isSameSalonDay(lateNight, earlySame, tz: lbv), isFalse);
    });

    test('a device-LOCAL instant is compared as its salon clock face', () {
      final deviceNow = DateTime.parse('2026-07-14T01:00:00+03:00').toLocal();
      final booking = DateTime.utc(2026, 7, 13, 23);
      expect(isSameSalonDay(deviceNow, booking), isTrue);
      expect(isSameSalonDay(deviceNow, DateTime.utc(2026, 7, 14, 9)), isFalse);
    });
  });

  group('salonToday / salonDayKey / salonDayBoundsUtc', () {
    final probe = DateTime.utc(2026, 7, 13, 23, 30);

    test('salonToday = the salon DATE identity (fields)', () {
      expect(salonToday(now: probe), DateTime.utc(2026, 7, 13));
      // 23:30Z = 00:30 Libreville on the 14th.
      final lbvToday = salonToday(now: probe, tz: lbv);
      expect(lbvToday.year, 2026);
      expect(lbvToday.month, 7);
      expect(lbvToday.day, 14);
    });

    test('salonDayKey rolls at the SALON midnight', () {
      expect(salonDayKey(probe), '2026-07-13');
      expect(salonDayKey(probe, tz: lbv), '2026-07-14');
      expect(
        salonDayKey(DateTime.parse('2026-07-08T02:36:00+03:00')),
        '2026-07-07', // the e2e flake's shape, still pinned
      );
    });

    test('salonDayBoundsUtc = the salon midnights as UTC instants', () {
      final ab = salonDayBoundsUtc(now: DateTime.utc(2026, 7, 13, 12));
      expect(ab.startUtc, DateTime.utc(2026, 7, 13));
      expect(ab.endUtc, DateTime.utc(2026, 7, 14));
      final lb = salonDayBoundsUtc(now: DateTime.utc(2026, 7, 13, 12), tz: lbv);
      expect(lb.startUtc, DateTime.utc(2026, 7, 12, 23));
      expect(lb.endUtc, DateTime.utc(2026, 7, 13, 23));
    });
  });

  group('salonDateTime / salonWallClockToUtc (picker wall-clock = salon)', () {
    test('builds the UTC instant of the salon wall-clock, serializes with Z',
        () {
      final picked = salonDateTime(2026, 7, 20, hour: 10, minute: 30);
      expect(picked.isUtc, isTrue);
      expect(picked.toIso8601String(), '2026-07-20T10:30:00.000Z');
      // The same wall-clock in Libreville is one hour earlier as an instant.
      final lbvPicked =
          salonDateTime(2026, 7, 20, hour: 10, minute: 30, tz: lbv);
      expect(lbvPicked.toIso8601String(), '2026-07-20T09:30:00.000Z');
      expect(
        salonWallClockToUtc(2026, 7, 20, hour: 9, tz: lbv),
        DateTime.utc(2026, 7, 20, 8),
      );
    });
  });

  group('toSalonTime / salonNow', () {
    test('toSalonTime renders the salon clock face, preserving the instant',
        () {
      final instant = DateTime.parse('2026-07-13T22:00:00+03:00');
      final abidjan = toSalonTime(instant);
      expect(abidjan.hour, 19); // 22:00+03:00 == 19:00 Abidjan
      final libreville = toSalonTime(instant, tz: lbv);
      expect(libreville.hour, 20); // == 20:00 Libreville
      expect(
        libreville.millisecondsSinceEpoch,
        instant.millisecondsSinceEpoch, // same instant
      );
    });

    test('salonNow keeps the current instant', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final now = salonNow(tz: lbv);
      expect(
        (now.millisecondsSinceEpoch - before).abs() < 5000,
        isTrue,
      );
    });
  });

  group('deviceOffsetDiffersFromSalon (the hint predicate)', () {
    final at = DateTime.utc(2026, 7, 13, 12);

    test('matrix against the DEFAULT salon (UTC+0)', () {
      expect(
        deviceOffsetDiffersFromSalon(deviceOffset: Duration.zero, at: at),
        isFalse,
      );
      expect(
        deviceOffsetDiffersFromSalon(
          deviceOffset: const Duration(hours: 1),
          at: at,
        ),
        isTrue,
      );
    });

    test('a device IN the salon zone offset never sees the hint', () {
      expect(
        deviceOffsetDiffersFromSalon(
          deviceOffset: const Duration(hours: 1),
          tz: lbv,
          at: at,
        ),
        isFalse,
      );
      expect(
        deviceOffsetDiffersFromSalon(
          deviceOffset: Duration.zero,
          tz: lbv,
          at: at,
        ),
        isTrue,
      );
    });
  });
}

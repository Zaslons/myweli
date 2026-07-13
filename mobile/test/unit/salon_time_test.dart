import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/salon_time.dart';

/// The salon-time seam (docs/design/timezone-salon-time.md §4). Probes are
/// explicit instants — never the process clock — so the suite is meaningful
/// on any machine timezone.
void main() {
  group('isSameSalonDay', () {
    test('across salon midnight, both directions', () {
      final lateNight = DateTime.utc(2026, 7, 13, 23, 50);
      final justAfter = DateTime.utc(2026, 7, 14, 0, 10);
      final earlySame = DateTime.utc(2026, 7, 13, 0, 10);
      expect(isSameSalonDay(lateNight, justAfter), isFalse);
      expect(isSameSalonDay(lateNight, earlySame), isTrue);
    });

    test('a device-LOCAL instant is compared as its salon clock face', () {
      // The pro-detail leak's exact shape: device-local "now" vs a UTC
      // booking. 01:00 UTC+3 on July 14 == 22:00Z July 13 → same salon day
      // as a 23:00Z July 13 booking, NOT the device's July 14.
      final deviceNow = DateTime.parse('2026-07-14T01:00:00+03:00').toLocal();
      final booking = DateTime.utc(2026, 7, 13, 23);
      expect(isSameSalonDay(deviceNow, booking), isTrue);
      expect(isSameSalonDay(deviceNow, DateTime.utc(2026, 7, 14, 9)), isFalse);
    });
  });

  group('salonToday / salonDayKey', () {
    test('salonToday truncates in salon time, flagged UTC', () {
      final t = salonToday(DateTime.utc(2026, 7, 13, 23, 59));
      expect(t, DateTime.utc(2026, 7, 13));
      expect(t.isUtc, isTrue);
    });

    test('salonDayKey rolls at salon midnight, not device midnight', () {
      expect(salonDayKey(DateTime.utc(2026, 7, 13, 23, 30)), '2026-07-13');
      expect(salonDayKey(DateTime.utc(2026, 7, 14, 0, 10)), '2026-07-14');
      // 02:36 on a UTC+3 device = 23:36Z the previous day (the e2e flake).
      expect(
        salonDayKey(DateTime.parse('2026-07-08T02:36:00+03:00')),
        '2026-07-07',
      );
    });
  });

  group('salonDateTime (picker wall-clock = salon time)', () {
    test('builds a UTC-flagged instant that serializes with Z', () {
      final picked = salonDateTime(2026, 7, 20, 10, 30);
      expect(picked.isUtc, isTrue);
      expect(picked.toIso8601String(), '2026-07-20T10:30:00.000Z');
    });
  });

  group('deviceOffsetDiffersFromSalon (the hint predicate)', () {
    test('matrix: salon offset → no hint; foreign offsets → hint', () {
      expect(
        deviceOffsetDiffersFromSalon(deviceOffset: Duration.zero),
        isFalse,
      );
      expect(
        deviceOffsetDiffersFromSalon(deviceOffset: const Duration(hours: 1)),
        isTrue, // Paris (winter)
      );
      expect(
        deviceOffsetDiffersFromSalon(deviceOffset: const Duration(hours: -5)),
        isTrue, // EST
      );
    });
  });

  group('toSalonTime / salonNow', () {
    test('toSalonTime never renders the device zone', () {
      final instant = DateTime.parse('2026-07-13T22:00:00+03:00');
      final salon = toSalonTime(instant);
      expect(salon.isUtc, isTrue);
      expect(salon.hour, 19); // 22:00+03:00 == 19:00 salon time
    });

    test('salonNow is UTC-flagged', () {
      expect(salonNow().isUtc, isTrue);
    });
  });
}

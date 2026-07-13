// Design: docs/design/timezone-salon-time.md — the mobile salon-time seam
// (docs/modules/multi-pays.md §3).
//
// THE RULE: storage/API is UTC; every displayed time and every day boundary
// is the SALON's time — never the device's. Today the salon timezone is
// Africa/Abidjan = UTC+0 (no DST), so salon time IS the UTC instant's clock
// face and these helpers are pure UTC math — no package:timezone needed. At
// multi-pays Wave 2 (per-salon timezone) only the helper BODIES change to an
// offset lookup from the salon's city; call sites stay untouched.

/// The salon timezone (IANA). The only place this fact lives on mobile.
const String kSalonTz = 'Africa/Abidjan';

/// The current instant, as a salon-time clock face.
DateTime salonNow() => DateTime.now().toUtc();

/// An instant re-expressed in salon time (what to feed the formatters —
/// NEVER `.toLocal()`, which renders the device's zone).
DateTime toSalonTime(DateTime d) => d.toUtc();

/// The salon-calendar date (midnight, date-only) containing `now`.
DateTime salonToday([DateTime? now]) {
  final s = toSalonTime(now ?? DateTime.now());
  return DateTime.utc(s.year, s.month, s.day);
}

/// Whether two instants fall on the same SALON calendar day.
bool isSameSalonDay(DateTime a, DateTime b) {
  final sa = toSalonTime(a);
  final sb = toSalonTime(b);
  return sa.year == sb.year && sa.month == sb.month && sa.day == sb.day;
}

/// The salon day key (`YYYY-MM-DD`) of an instant — the one legal home of
/// the `.toIso8601String().substring(0, 10)` idiom.
String salonDayKey(DateTime d) =>
    toSalonTime(d).toIso8601String().substring(0, 10);

/// A wall-clock the user picked (date/time pickers) IS salon time: build the
/// instant explicitly so it serializes with a `Z` instead of leaning on the
/// server's process timezone.
DateTime salonDateTime(int year, int month, int day,
        [int hour = 0, int minute = 0]) =>
    DateTime.utc(year, month, day, hour, minute);

/// Whether the device clock disagrees with the salon's — drives the
/// « Heures affichées : heure du salon (Côte d'Ivoire) » hint. Injectable
/// offset for tests.
bool deviceOffsetDiffersFromSalon({Duration? deviceOffset}) =>
    (deviceOffset ?? DateTime.now().timeZoneOffset) != Duration.zero;

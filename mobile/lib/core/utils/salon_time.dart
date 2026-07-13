// Design: docs/design/multi-pays-end-version.md §3 — the mobile salon-time
// seam (docs/modules/multi-pays.md §3; supersedes the slice-1 UTC-only
// header: the Wave-2 flip is EXECUTED, MP2).
//
// THE RULE: storage/API is UTC; every displayed time and every day boundary
// is the SALON's time — never the device's. The salon's IANA timezone rides
// its provider payload (server-derived from its city — threat T57); helpers
// take it as `{String? tz}` and fall back to Africa/Abidjan (Wave 0), so
// every pre-MP2 call site keeps its exact behavior.
//
// latest_all (NOT latest_10y): the trimmed set drops LINK zones — and most
// of francophone Africa's IANA names are links (Africa/Libreville /
// Porto-Novo / Niamey → Africa/Lagos). The MP1 backend hit this; the app
// accepts the APK cost for Wave-2/3 correctness.

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tzdb;

/// The DEFAULT salon timezone (IANA) — Wave 0. The only place this fact
/// lives on mobile; per-salon values come from the API.
const String kSalonTz = 'Africa/Abidjan';

bool _initialized = false;

/// Loads the bundled tz database. Idempotent; called at app boot (the three
/// `main()`s) and lazily by [locationOf] so tests never need explicit setup.
void initSalonTime() {
  if (_initialized) return;
  tzdata.initializeTimeZones();
  _initialized = true;
}

final Map<String, tzdb.Location> _locations = {};

/// The tz database location for an IANA name; null/unknown → Abidjan.
tzdb.Location locationOf(String? tz) {
  initSalonTime();
  final name = tz ?? kSalonTz;
  final cached = _locations[name];
  if (cached != null) return cached;
  tzdb.Location location;
  try {
    location = tzdb.getLocation(name);
  } on tzdb.LocationNotFoundException {
    location = tzdb.getLocation(kSalonTz);
  }
  return _locations[name] = location;
}

/// The current instant, as the salon's clock face.
DateTime salonNow({String? tz}) => toSalonTime(DateTime.now(), tz: tz);

/// An instant re-expressed in salon time (what to feed the formatters —
/// NEVER `.toLocal()`, which renders the device's zone). The returned value
/// keeps the same instant (epoch) with the salon's wall-clock fields.
DateTime toSalonTime(DateTime d, {String? tz}) =>
    tzdb.TZDateTime.from(d.toUtc(), locationOf(tz));

/// The salon-calendar DATE (date-only identity — fields are the salon day;
/// feed pickers/calendars, NOT range queries — see [salonDayBoundsUtc]).
DateTime salonToday({DateTime? now, String? tz}) {
  final s = toSalonTime(now ?? DateTime.now(), tz: tz);
  return DateTime.utc(s.year, s.month, s.day);
}

/// The UTC instants of [00:00, next 00:00) SALON time for the salon day
/// containing `now` — range-query boundaries (earnings/list filters).
({DateTime startUtc, DateTime endUtc}) salonDayBoundsUtc({
  DateTime? now,
  String? tz,
}) {
  final location = locationOf(tz);
  final s = tzdb.TZDateTime.from((now ?? DateTime.now()).toUtc(), location);
  final start = tzdb.TZDateTime(location, s.year, s.month, s.day);
  final end = tzdb.TZDateTime(location, s.year, s.month, s.day + 1);
  return (startUtc: start.toUtc(), endUtc: end.toUtc());
}

/// The UTC instant of a salon wall-clock on a calendar day — range starts
/// for week/month buckets and picker round-trips.
DateTime salonWallClockToUtc(
  int year,
  int month,
  int day, {
  int hour = 0,
  int minute = 0,
  String? tz,
}) =>
    tzdb.TZDateTime(locationOf(tz), year, month, day, hour, minute).toUtc();

/// Whether two instants fall on the same SALON calendar day.
bool isSameSalonDay(DateTime a, DateTime b, {String? tz}) {
  final sa = toSalonTime(a, tz: tz);
  final sb = toSalonTime(b, tz: tz);
  return sa.year == sb.year && sa.month == sb.month && sa.day == sb.day;
}

/// The salon day key (`YYYY-MM-DD`) of an instant — the one legal home of
/// the day-key idiom.
String salonDayKey(DateTime d, {String? tz}) {
  final s = toSalonTime(d, tz: tz);
  final mm = s.month.toString().padLeft(2, '0');
  final dd = s.day.toString().padLeft(2, '0');
  return '${s.year.toString().padLeft(4, '0')}-$mm-$dd';
}

/// A wall-clock the user picked (date/time pickers) IS salon time: build the
/// UTC instant of that salon wall-clock (serializes with a `Z`).
DateTime salonDateTime(
  int year,
  int month,
  int day, {
  int hour = 0,
  int minute = 0,
  String? tz,
}) =>
    tzdb.TZDateTime(locationOf(tz), year, month, day, hour, minute).toUtc();

/// Whether the device clock disagrees with the salon's at [at] — drives the
/// « Heures affichées : heure du salon » hint. Injectable offset for tests.
bool deviceOffsetDiffersFromSalon({
  Duration? deviceOffset,
  String? tz,
  DateTime? at,
}) {
  final instant = at ?? DateTime.now();
  final salonOffset =
      locationOf(tz).timeZone(instant.millisecondsSinceEpoch).offset;
  return (deviceOffset ?? instant.timeZoneOffset) != salonOffset;
}

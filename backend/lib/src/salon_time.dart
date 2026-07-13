// latest_all (NOT latest_10y): the trimmed set drops LINK zones — and most
// of francophone Africa's IANA names are links (Africa/Libreville /
// Porto-Novo / Niamey → Africa/Lagos). Size is irrelevant server-side;
// correctness for Wave-2/3 markets is not.
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// Design: docs/design/multi-pays-end-version.md §3 — the backend salon-time
// seam (docs/modules/multi-pays.md §3).
//
// THE RULE: storage stays UTC; every DAY BOUNDARY (« aujourd'hui » gates,
// journal days, revenue buckets, off-day masking, slot construction) and
// every human-rendered time (message templates) is computed in the SALON's
// IANA timezone — read from the provider document (`timezone`), derived from
// its city, never client-sent (threat T57). Unknown/absent timezones fall
// back to Africa/Abidjan (Wave 0). Admin analytics stays platform-UTC by
// design.

bool _initialized = false;

/// Loads the bundled tz database (10-year window — plenty: no target market
/// observes DST). Idempotent; called at boot and lazily by [locationOf] so
/// tests never need explicit setup.
void initSalonTime() {
  if (_initialized) return;
  tzdata.initializeTimeZones();
  _initialized = true;
}

const String kDefaultSalonTz = 'Africa/Abidjan';

final Map<String, tz.Location> _locations = {};

/// The tz database location for an IANA name; null/unknown → Abidjan.
tz.Location locationOf(String? tzName) {
  initSalonTime();
  final name = tzName ?? kDefaultSalonTz;
  final cached = _locations[name];
  if (cached != null) return cached;
  tz.Location location;
  try {
    location = tz.getLocation(name);
  } on tz.LocationNotFoundException {
    location = tz.getLocation(kDefaultSalonTz);
  }
  return _locations[name] = location;
}

/// Whether two instants fall on the same SALON calendar day.
bool sameSalonDay(DateTime a, DateTime b, String? tzName) {
  final location = locationOf(tzName);
  final la = tz.TZDateTime.from(a.toUtc(), location);
  final lb = tz.TZDateTime.from(b.toUtc(), location);
  return la.year == lb.year && la.month == lb.month && la.day == lb.day;
}

/// The salon day key (`YYYY-MM-DD`) of an instant.
String salonDayKey(DateTime d, String? tzName) {
  final l = tz.TZDateTime.from(d.toUtc(), locationOf(tzName));
  final mm = l.month.toString().padLeft(2, '0');
  final dd = l.day.toString().padLeft(2, '0');
  return '${l.year}-$mm-$dd';
}

/// The UTC instants of [00:00, next 00:00) SALON time for the salon day
/// containing [anyInstant] (or, for a date-only value, that calendar day).
({DateTime startUtc, DateTime endUtc}) salonDayBoundsUtc(
  DateTime anyInstant,
  String? tzName,
) {
  final location = locationOf(tzName);
  final l = tz.TZDateTime.from(anyInstant.toUtc(), location);
  final start = tz.TZDateTime(location, l.year, l.month, l.day);
  final end = tz.TZDateTime(location, l.year, l.month, l.day + 1);
  return (startUtc: start.toUtc(), endUtc: end.toUtc());
}

/// The UTC instants of the salon day for a CALENDAR DATE's y/m/d fields —
/// how a `?date=YYYY-MM-DD` query names a salon day (the fields are read as
/// salon wall-clock, whatever flag the parsed DateTime carries).
({DateTime startUtc, DateTime endUtc}) salonCalendarDayBoundsUtc(
  DateTime calendarDate,
  String? tzName,
) {
  final location = locationOf(tzName);
  final start = tz.TZDateTime(
    location,
    calendarDate.year,
    calendarDate.month,
    calendarDate.day,
  );
  final end = tz.TZDateTime(
    location,
    calendarDate.year,
    calendarDate.month,
    calendarDate.day + 1,
  );
  return (startUtc: start.toUtc(), endUtc: end.toUtc());
}

/// The UTC instant of a salon wall-clock: [minutesOfDay] past midnight on the
/// calendar day y/m/d, in the salon's timezone (slot construction).
DateTime salonWallClockToUtc(
  int year,
  int month,
  int day,
  int minutesOfDay,
  String? tzName,
) {
  final location = locationOf(tzName);
  return tz.TZDateTime(
    location,
    year,
    month,
    day,
    minutesOfDay ~/ 60,
    minutesOfDay % 60,
  ).toUtc();
}

/// Salon wall-clock components of an instant (message templates, weekday
/// resolution for schedules).
tz.TZDateTime salonWallClock(DateTime d, String? tzName) =>
    tz.TZDateTime.from(d.toUtc(), locationOf(tzName));

/// The bookable window: how soon, and how far ahead, a salon takes bookings.
///
/// A14d (§21 row 76). Before this, neither end was a rule. The far end existed
/// only as a client-side literal — `kBookingHorizon` in the app, and nothing at
/// all on the server, so a client could request slots for any date in any year
/// and the server would compute them. The near end was worse: a bare `60`
/// inside `slot_service.dart`'s slot loop, with no constant, no setting and no
/// test, duplicated independently in the mobile mock as `Duration(hours: 1)`.
///
/// **Both defaults preserve today's behaviour exactly**, so the day A14d ships
/// no salon's calendar changes. The feature is the ability to change them.
///
/// **Client paths only.** `bookManual` never reaches the slot engine, and the
/// salon's own reschedules pass `enforceBookingWindow: false` — the salon owns
/// its calendar (see `slot_service.dart`). These bounds constrain what a CLIENT
/// may ask for, not what a salon may do.
library;

/// Matches the app's `kBookingHorizon` (365), so the funnel's existing reach is
/// unchanged for a salon that never touches the setting.
const int kDefaultBookingHorizonDays = 365;

/// The literal `slot_service.dart` already enforced, now named and per-salon.
const int kDefaultMinimumNoticeMinutes = 60;

/// One day is the shortest meaningful horizon — 0 would mean « nothing is ever
/// bookable », which is a mistake rather than a setting, and salons that want
/// to stop taking bookings suspend or unpublish instead.
const int kMinBookingHorizonDays = 1;

/// Two years. Generous against every competitor we checked (Square caps at
/// 365) and, crucially, **finite**: `MyweliMonthNavigator` builds a year list
/// from `firstDate.year` to `lastDate.year`, so an unbounded horizon is an
/// unbounded `ListView` on a low-end Android. `bufferMinutes` — the only
/// numeric precedent in this document — has no ceiling at all (`999999999`
/// validates and stores today), so this is a new pattern rather than a copy.
const int kMaxBookingHorizonDays = 730;

/// Walk-ins welcome.
const int kMinMinimumNoticeMinutes = 0;

/// Seven days. Past this a salon is really describing a horizon, not a notice.
const int kMaxMinimumNoticeMinutes = 7 * 24 * 60;

/// Whether a window leaves anything at all bookable.
///
/// A notice that reaches past the horizon means every day is simultaneously
/// too soon and too far — the salon is unreachable, silently, with a valid
/// document. That is a mistake, not a configuration, so the validator refuses
/// it rather than letting a salon disappear from the funnel with a 200.
bool isBookableWindow({
  required int bookingHorizonDays,
  required int minimumNoticeMinutes,
}) => minimumNoticeMinutes <= bookingHorizonDays * 24 * 60;

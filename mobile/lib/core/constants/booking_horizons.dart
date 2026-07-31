/// How far ahead each date picker lets a user go (A14).
///
/// **These were five inline literals before this file existed**, and they did
/// not agree: the consumer booking hub offered **365** days, the pro manual
/// booking **90**, the journal's day-jump `DateTime.utc(2024)`..`utc(2030)`, and
/// the consumer's *other* date screen — `date_time_selection_screen`, a second
/// widget doing the same job — **90** (deleted in A14c; its 90 died with it). Nothing named any of them and nothing
/// explained the disagreement.
///
/// **There is no server rule to defer to.** The backend has no bookable-horizon
/// concept at all; the only `90` in `backend/` is `kProTrialDays`, which is the
/// subscription trial and unrelated. So these are product decisions, and until
/// they are taken deliberately they are at least named, in one place, where the
/// disagreement is visible instead of scattered.
///
/// A14 does **not** reconcile the consumer funnel's 365-vs-90 split — that is a
/// product question about how far ahead a salon accepts bookings, not a widget
/// change, and it has its own register row.
library;

/// The consumer booking funnel, and every pro flow that schedules forward.
///
/// One year. Long enough that no real appointment is refused by the picker, and
/// short enough that the month navigation stays finite.
const Duration kBookingHorizon = Duration(days: 365);

/// The pro's manual booking form.
///
/// Ninety days, inherited rather than chosen: a receptionist taking a walk-in
/// is scheduling weeks out, not a year. Kept distinct from [kBookingHorizon] so
/// the difference is a decision someone can find and revisit, rather than two
/// literals that happen to differ.
const Duration kManualBookingHorizon = Duration(days: 90);

/// How far **back** the pro journal may be navigated.
///
/// The journal is the only past-facing picker: a pro looks up what happened
/// last month. It was `DateTime.utc(2024)`..`utc(2030)` — two magic years, with
/// no data before 2024 and an invented ceiling. Expressed as a span around the
/// current day instead, so it cannot expire.
const Duration kJournalPastHorizon = Duration(days: 365);

/// How far ahead each date picker lets a user go (A14).
///
/// **These were five inline literals before this file existed**, and they did
/// not agree: the consumer booking hub offered **365** days, the pro manual
/// booking **90**, the journal's day-jump `DateTime.utc(2024)`..`utc(2030)`, and
/// the consumer's *other* date screen — `date_time_selection_screen`, a second
/// widget doing the same job — **90** (deleted in A14c; its 90 died with it). Nothing named any of them and nothing
/// explained the disagreement.
///
/// **There WAS no server rule to defer to, and now there is.** This paragraph
/// used to end « the backend has no bookable-horizon concept at all », and
/// A14d made that false in the same campaign that wrote it: the bookable window
/// is now a per-salon setting the server enforces —
/// `backend/lib/src/appointments/booking_window.dart` is the authority, and the
/// two defaults below mirror it field for field.
///
/// So the constants that remain are **fallbacks, not the rule**. A salon's own
/// window arrives on `Provider.availability` and beats them everywhere a client
/// books; these values answer only « what if we have no salon in hand yet »
/// (a picker opened before the provider loads) and « what does a pro flow use »
/// (the pro is exempt — the salon owns its calendar).
library;

/// The consumer booking funnel's FALLBACK, and every pro flow that schedules
/// forward.
///
/// One year. Long enough that no real appointment is refused by the picker, and
/// short enough that the month navigation stays finite. Since A14d a consumer
/// surface prefers the salon's own [Availability.bookingHorizonDays] and falls
/// back here only when no salon is in hand.
const Duration kBookingHorizon = Duration(days: 365);

/// The far end of the bookable window when a salon has not set one.
///
/// Mirrors `kDefaultBookingHorizonDays` in
/// `backend/lib/src/appointments/booking_window.dart`, which is the authority.
/// Equal to [kBookingHorizon] by construction and by intent: A14d changed no
/// salon's reach on the day it shipped, and if these two ever diverge the app
/// would offer a different year than the server accepts.
const int kDefaultBookingHorizonDays = 365;

/// The near end: how soon before a start a client may still book.
///
/// Mirrors `kDefaultMinimumNoticeMinutes` in the same backend file. Sixty
/// minutes is not a new product decision — it is the literal the slot engine
/// already enforced, unnamed and untested, on both the server and the mobile
/// mock. A14d named it and made it per-salon; this is what a salon that never
/// touches the setting still gets.
const int kDefaultMinimumNoticeMinutes = 60;

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

/// What the pro's « Fenêtre de réservation » card offers.
///
/// Public and here rather than private to the screen so a test can assert the
/// one property the lists must satisfy together: **no pair may put the notice
/// past the horizon**, which the server refuses as `invalid_input`
/// (`isBookableWindow`). A salon must never be offered a chip that fails.
abstract final class BookingWindowPresets {
  /// 1 mois · 3 mois · 6 mois · 1 an.
  static const List<int> horizons = [30, 90, 180, 365];

  /// Aucun · 1 h · 12 h · 24 h. The widest is inside the shortest horizon by
  /// construction — 1440 minutes against 30 × 1440.
  static const List<int> notices = [0, 60, 720, 1440];
}

/// One « Horaires de travail » starting point a salon applies in a tap and
/// edits afterwards (docs/design/availability-presets.md).
typedef WeeklySchedulePreset = ({
  String label,
  Set<int> days,
  int startHour,
  int endHour,
});

/// What the pro's hours section offers as models (curation feedback
/// 2026-08-26).
///
/// Public and here beside [BookingWindowPresets] for the same reason it is:
/// a test asserts the properties the list must satisfy — no preset may
/// produce end ≤ start, days are a non-empty subset of 0..6 (0 = Lundi, the
/// `weeklySchedule` convention), labels are unique — and the LABELS are
/// pinned character-for-character against the web's `SCHEDULE_PRESETS`
/// (identical French on both surfaces is the product rule, not a
/// coincidence). « – » is the en dash and « · » the middot, the A14d chip
/// idiom (`horizonLabel`).
abstract final class WeeklySchedulePresets {
  static const List<WeeklySchedulePreset> all = [
    (
      label: 'Mar–Sam · 9h–18h',
      days: {1, 2, 3, 4, 5},
      startHour: 9,
      endHour: 18,
    ),
    (
      label: 'Lun–Sam · 8h–17h',
      days: {0, 1, 2, 3, 4, 5},
      startHour: 8,
      endHour: 17,
    ),
    (
      label: 'Tous les jours · 9h–19h',
      days: {0, 1, 2, 3, 4, 5, 6},
      startHour: 9,
      endHour: 19,
    ),
  ];
}

/// The créneaux explainer under both platforms' hours headings — the one
/// section of four with no explanatory sentence, on the exact question the
/// owner fielded while curating (« où crée-t-on les créneaux ? » — nulle
/// part : ils sont dérivés). Identical on web (`CRENEAUX_COPY`), pinned.
const String kCreneauxCopy =
    'Vos créneaux de réservation sont calculés automatiquement à partir de '
    'ces horaires et de la durée de chaque prestation.';

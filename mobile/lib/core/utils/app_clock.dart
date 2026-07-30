/// The app's clock seam (SYSTEM.md §18, A10) — the "which instant" half of
/// salon time, which `salon_time.dart` does not own.
///
/// **Why this exists.** §18 already rules that displayed times and day
/// boundaries are the SALON's, never the device's — but it governs which *zone*
/// a time renders in, not which *instant* "now" is. Nothing owned that, so the
/// wall clock reached 38 render-path sites directly, and two pro screens could
/// not be photographed at all: a golden of either would be "a picture of the day
/// it was taken" (§20.1, §21 row 23).
///
/// **Why a function pointer and not `package:clock`.** Zones were the first
/// choice and were measured to be the wrong one here:
///
///   * `flutter_test`'s binding **already** overrides the ambient `clock` with a
///     `FakeAsync` seeded from the *real* wall clock at test start — so
///     `clock.now()` inside a widget test is non-deterministic before we add
///     anything;
///   * `fake_async` captures a timer's zone at **creation**, not at firing, so
///     the mocks' 300 ms `AppConstants.mockDelay` and the pro golden's
///     `runAsync` sign-in both escape a body-level `withClock`;
///   * `MockData.appointments` is `static final` — memoised per isolate at first
///     touch, in whatever zone touched it first. No zone reaches it afterwards;
///   * importing `package:clock` in `lib/` without a pubspec entry trips
///     `depend_on_referenced_packages`, which is an *info*, which is **CI red**
///     under `--fatal-infos`.
///
/// A function pointer has none of those properties: it does not care which zone
/// the caller is in, so it reaches field initializers, timers and `static final`
/// seeds alike.
///
/// **The house shape** (`salon_time.dart`, `app_locale.dart`): free functions in
/// `core/`, no DI, no interface, and injection as an optional named parameter
/// defaulting to the ambient source — which four helpers in `salon_time.dart`
/// and `Formatters.formatRelative` already do. This is the ambient source they
/// default *to*.
///
/// Pinned by `test/unit/salon_time_pin_test.dart`: no `DateTime.now()` outside
/// this file, bar declared exemptions.
class AppClock {
  AppClock._();

  static DateTime Function() _source = DateTime.now;

  /// The current instant. **Every render-path clock read goes through here.**
  ///
  /// For salon-facing values, prefer `salonNow()` / `salonToday()` — they call
  /// this and then apply §18's timezone rule. Reading this directly renders the
  /// *device's* wall clock, which §18 forbids for anything a user sees.
  static DateTime now() => _source();

  /// Pin the clock to [instant]; returns the restore function.
  ///
  /// **The global is the trade for reaching zone-less call sites**, so the
  /// tear-down is not optional — a leaked freeze makes the *next* test read a
  /// constant, which passes far more often than it fails. Tests use
  /// `test/support/frozen_clock.dart`'s `freezeClock`, which wires
  /// `addTearDown` for the caller. Production code never calls this.
  static void Function() freeze(DateTime instant) {
    final previous = _source;
    _source = () => instant;
    return () => _source = previous;
  }

  /// Restore the wall clock. Idempotent.
  static void restore() => _source = DateTime.now;
}

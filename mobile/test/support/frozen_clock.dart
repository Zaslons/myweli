import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/services/mock/mock_data.dart';

/// Pin [AppClock] for one test, with the tear-down wired for the caller.
///
/// **The tear-down is the whole reason this helper exists.** `AppClock.freeze`
/// mutates a static, which is the deliberate trade for reaching field
/// initializers, timers and `static final` seeds that no zone can touch. A
/// leaked freeze does not fail loudly — it makes every subsequent test in the
/// isolate read a constant, which passes more often than it fails. A8 learned
/// the same lesson from `accessibilityFeaturesTestValue` being process-global.
void freezeClock(DateTime instant) {
  final restore = AppClock.freeze(instant);
  addTearDown(restore);

  // **Freezing without re-seeding is a freeze that looks like it worked.**
  // `MockData`'s appointment and team seeds are RELATIVE (`now + 2 days`), and
  // the lists are `static final` — memoised per isolate at first touch. Whoever
  // touched them first wins, so a frozen clock alone leaves stale data and the
  // assertion fails for a reason that has nothing to do with the code under
  // test. Both resets keep their list instances, so writes made by the code
  // under test still land.
  MockData.resetAppointments();
  MockData.resetTeam();
  addTearDown(() {
    MockData.resetAppointments();
    MockData.resetTeam();
  });
}

/// A Wednesday, mid-month, mid-year — the default fixture instant.
///
/// Chosen so the journal's week strip spans a single month (9–15 March), which
/// makes the expected day numbers readable in an assertion instead of wrapping
/// across a month boundary. Mid-month also keeps it clear of the
/// last-two-days-of-the-month case that flips the dashboard's `monthRevenue`,
/// so that flake gets its own explicit date rather than hiding in the default.
final DateTime kFixedNow = DateTime.utc(2026, 3, 11, 10, 30);

/// The last day of a 31-day month — the dashboard's real flake.
///
/// `MockData` seeds an appointment at `now + 2 days`, so on the last two days of
/// a month it falls into the NEXT month and `monthRevenue` drops to zero.
final DateTime kMonthEdgeNow = DateTime.utc(2026, 3, 31, 10, 30);

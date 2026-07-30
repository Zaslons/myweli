import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/screens/provider/journal/pro_journal_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/pump_app.dart';

/// A10 — the app renders what the clock says, not what the machine says
/// (SYSTEM.md §18, §20.1, §21 row 23).
///
/// **Why the seam ships in this commit rather than the sweep's.** Every prior
/// slice gated against a lever that already existed — A8 had the OS
/// accessibility flag, A9 had `MaterialLocalizations` returning English. A10 has
/// none: **you cannot freeze a clock before a freeze mechanism exists.** So
/// `core/utils/app_clock.dart` lands here with **no call site converted**, and
/// the two screen assertions below are red because the product ignores it. Same
/// shape as A8's ①, which shipped `test/a11y/_motion.dart` as harness alongside
/// its reds.
///
/// **What these assertions are NOT.** They are not "today". A gate that pins
/// today passes on the day it is written and rots by morning — which is exactly
/// the defect row 23 describes. Every expectation below is a **fixed** value
/// derived from a **frozen** instant, so it is wrong on 364 days out of 365
/// until the sweep lands, and right on all 365 afterwards.
///
/// **What this gate does NOT reach**, stated rather than discovered later: it
/// pumps two screens. Six more read the clock on a render path
/// (`earnings_screen`, `appointment_list_screen`, `appointment_calendar_view`,
/// `pro_manual_booking_screen`, `availability_screen`,
/// `pro_subscription_screen`), and two goldens that already exist contain clock
/// reads. Those are covered by the PIN, not by this file — and the pin is a
/// weaker instrument, because it only sees `DateTime.now()` tokens while 19
/// render-path sites call the seam with `now:` omitted and carry no token at
/// all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = MockProService();
  });

  group('the seam itself', () {
    test('defaults to the wall clock — the control', () {
      // Without this, every assertion below would pass on a seam that always
      // returned a constant. It is also the one thing `salon_time_test.dart:104`
      // already asserts for `salonNow`, and the reason that test must keep
      // asserting it after the sweep rather than being frozen with the rest.
      final drift = AppClock.now().difference(DateTime.now()).abs();
      expect(drift.inSeconds, lessThan(5));
    });

    test('freezes, and restores', () {
      final restore = AppClock.freeze(DateTime.utc(2026, 3, 11));
      // **Belt as well as braces, and the braces were missing.** `expect` throws,
      // so a failure on the next line would skip the manual `restore()` below and
      // leave the isolate pinned to 11 March 2026 — the exact instant the journal
      // gate two tests down asserts. One failure here would have turned that gate
      // into a tautology that passes whether or not `freezeClock` works. This
      // file's own prose names that hazard; this was the one place it was not
      // guarded against.
      addTearDown(restore);
      expect(AppClock.now(), DateTime.utc(2026, 3, 11));
      restore();
      expect(
        AppClock.now().difference(DateTime.now()).abs().inSeconds,
        lessThan(5),
        reason:
            'a leaked freeze makes the NEXT test read a constant, which '
            'passes far more often than it fails — so the restore is the '
            'half of the seam that keeps the suite honest',
      );
    });
  });

  group('§21 row 23 — the two screens that cannot be photographed', () {
    Widget journalApp() => wrapApp(
      providers: [
        ChangeNotifierProvider(create: (_) => ProAuthProvider()),
        ChangeNotifierProvider(create: (_) => ProJournalProvider()),
      ],
      routerConfig: GoRouter(
        initialLocation: '/pro/journal',
        routes: [
          GoRoute(
            path: '/pro/journal',
            builder: (_, _) => const ProJournalScreen(),
          ),
          GoRoute(
            path: '/pro/appointment/new',
            builder: (_, _) => const Scaffold(body: Text('MANUEL')),
          ),
          GoRoute(
            path: '/pro/appointment/:id',
            builder: (_, _) => const Scaffold(body: Text('DETAIL')),
          ),
          GoRoute(
            path: '/pro/appointments',
            builder: (_, _) => const Scaffold(body: Text('AGENDA')),
          ),
        ],
      ),
    );

    /// The house `settle()` ladder, **run eight times**.
    ///
    /// `test/widget/pro_journal_screen_test.dart` gets away with three pumps
    /// because its `_StubProService` returns synchronously. This file drives the
    /// real `MockProService`, and `ProJournalProvider.load` is not one delay —
    /// it awaits `getJournalDay` (300 ms), then fires `_prefetchWeekCounts`
    /// (`:181`), which awaits **six more sequentially**, one per week-strip pill
    /// that is not the selected day. Three pumps leaves five in flight and the
    /// test dies on `!timersPending` at tear-down — which is how this was
    /// found, *after* the assertion it was hiding had already gone green.
    ///
    /// `pumpAndSettle` is not the fix: the house forbids it (infinite Lottie).
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.pump();
    }

    testWidgets('the journal week strip is the frozen week, not this week', (
      tester,
    ) async {
      // Row 23 says the journal "prints TODAY's date into its header". Measured,
      // the header is STABLE — `isToday` is always true on the default path, so
      // it reads « Aujourd'hui » every day. The flake is the strip
      // (`pro_journal_screen.dart:536`): `monday = selected.subtract(weekday-1)`
      // and seven pills each printing `${d.day}` (`:590`).
      //
      // 11 March 2026 is a Wednesday, so its week is 9–15 March — one month, no
      // wrap, and therefore an assertion a human can check by eye.
      freezeClock(kFixedNow);
      await tester.pumpWidget(journalApp());
      await settle(tester);

      for (final day in ['9', '10', '11', '12', '13', '14', '15']) {
        expect(
          find.text(day),
          findsWidgets,
          reason:
              'the strip must render the FROZEN week. Today it renders '
              'the machine’s, which is why this screen has never been '
              'goldened.',
        );
      }
      expect(
        find.text('Aujourd’hui'),
        findsOneWidget,
        reason:
            'and the header stays « Aujourd’hui » — the part row 23 '
            'blamed is the part that was already fine',
      );
    });

    testWidgets('…and a different frozen week gives a different strip', (
      tester,
    ) async {
      // The other leg. Without it the assertion above is satisfied by a strip
      // that renders 9–15 unconditionally — which is what a badly-written fix
      // (hard-coding the fixture date) would produce.
      freezeClock(DateTime.utc(2026, 6, 17, 10, 30)); // Wed, week 15–21 June
      await tester.pumpWidget(journalApp());
      await settle(tester);

      for (final day in ['15', '16', '17', '18', '19', '20', '21']) {
        expect(find.text(day), findsWidgets);
      }
      expect(
        find.text('9'),
        findsNothing,
        reason:
            'March must not leak into June — the strip follows the clock, '
            'it is not pinned to the fixture',
      );
    });

    test('the dashboard month bucket follows the frozen clock', () async {
      // **Asserted at the SERVICE, not the screen, and that is deliberate.**
      // The first version of this pumped `DashboardScreen` and looked for
      // « 5 000 FCFA » — and was red with `Actual: <0>` on BOTH legs, because it
      // never signed in and the money cards are role-gated behind
      // `stats.hasRevenue` (`dashboard_screen.dart:256`). A gate that is red
      // because the widget never renders is a gate that cannot go green: the
      // exact defect A9 shipped when `addTearDown(handle.dispose)` made its
      // semantics tests unpassable. The screen-level proof is the golden in ④;
      // this asserts the mechanism.
      //
      // Row 23 blames "weekly stat cards". There is no week card — `weekday`
      // reaches only `weekRevenue`, which no screen reads
      // (`dashboard_screen.dart` renders todayAppointments · pendingRequests ·
      // todayRevenue · monthRevenue). The real flake is monthly: `MockData`
      // seeds an appointment at `now + 2 days`, so on the last two days of a
      // month it lands in the NEXT month and `monthRevenue` drops to zero.
      //
      // `canSeeMoney` is `row == null || …`, so with no session the figures are
      // present — no auth flow needed to see them.
      final service = MockProService();

      freezeClock(kFixedNow);
      final midMonth = (await service.getDashboardStats('provider1')).data!;

      freezeClock(kMonthEdgeNow);
      final monthEdge = (await service.getDashboardStats('provider1')).data!;

      expect(
        midMonth.monthRevenue,
        isNot(monthEdge.monthRevenue),
        reason:
            'the month bucket must follow the FROZEN clock. Equal means '
            'the mock still reads the machine — and `MockData.appointments` '
            'is `static final`, memoised at first touch, so no zone-based '
            'fix could ever have reached it either.',
      );
    });
  });
}

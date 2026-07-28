import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_earnings_provider.dart';
import 'package:myweli/providers/pro_reviews_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/appointments/my_bookings_screen.dart';
import 'package:myweli/screens/auth/otp_verify_screen.dart';
import 'package:myweli/screens/home/home_screen.dart';
import 'package:myweli/screens/provider/appointments/appointment_list_screen.dart';
import 'package:myweli/screens/provider/auth/pro_otp_verify_screen.dart';
import 'package:myweli/screens/provider/earnings/earnings_screen.dart';
import 'package:myweli/screens/provider/reviews/reviews_screen.dart';
import 'package:myweli/widgets/common/legal_consent_text.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fonts.dart';
import '../support/frozen_clock.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';
import '_a11y.dart';

/// **A width is not all widths** (docs/design/mobile-a11-width.md, SYSTEM.md §10).
///
/// §10 defines `compact` as a RANGE — everything under 600dp, with no floor —
/// and every rendering test in this repo measured a single point inside it:
/// `kGoldenPhone`, 390×844, an iPhone 14. The modal Android device in Côte
/// d'Ivoire is **360dp** (Tecno/Infinix/itel at 720×1600), and 375 is every
/// small iPhone. Two of the three widths §10 promises had never been rendered
/// once, by anything.
///
/// This file renders all three, at 1× and at 2× text (§13.3 — 200% is a
/// first-class input, not an edge case), and asserts three things per screen:
///
///  **A** nothing overflowed — `tester.takeException()`;
///  **B** no text is cut off without saying so — [expectNoUndeclaredTruncation];
///  **C** the screen actually rendered its content.
///
/// ## C is not a formality, and it is the assertion most likely to be deleted
///
/// A width gate that lands on an empty state measures the padding around
/// « Aucun rendez-vous » and reports green. Two subjects here reach their empty
/// state by default: `AppointmentListScreen`'s « Liste » tab opens on
/// « Aujourd'hui », whose bounds `MockData` never seeds (`provider1` sits at
/// `now + 2d`, `now - 10d`, `now - 7d` — never today), and `HomeScreen` hides
/// BOTH of the headings this slice is about behind `isAuthenticated`
/// (`home_screen.dart:234,330`), so the signed-out pump the goldens use never
/// rendered either one. §20 names this vacuity twice; C is what makes the
/// difference visible.
///
/// ## Why the loops are outside `testWidgets`, measured
///
/// `_overflowReportNeeded` latches false the first time a RenderFlex reports,
/// and only `reassemble()` resets it (`debug_overflow_indicator.dart:127,327`).
/// `pumpWidget` re-uses the render objects, so a width loop INSIDE one test
/// measures the first width and silently skips the rest.
///
/// This is not a reading of the source — it was run, on the OTP screen, which
/// overflows at 360 AND at 375:
///
/// ```text
///   PROBE outside 360.0 -> reported     one testWidgets per width
///   PROBE outside 375.0 -> reported
///   PROBE inside  360.0 -> reported     one testWidgets, looping
///   PROBE inside  375.0 -> NO REPORT    ← the bug is still there
/// ```
///
/// So the tidier-looking shape is green at 375 about a screen that is broken at
/// 375. One `testWidgets` per (width, scale) gives each configuration a fresh
/// binding, and names itself in the failure output. **Do not collapse it.**
///
/// DI note: this file calls `setupDependencyInjection()` and hand-assigns
/// nothing. The locator's fields are `late final` — assignable once per isolate
/// — so it is one or the other, never both.
void main() {
  /// The three points §10's `compact` range actually has to hold.
  const widths = <double>[360, 375, 390];

  /// 1× and the §13.3 floor. Not a sweep: 2× is where a layout that cannot grow
  /// gives up, and 1× is where it must already be correct.
  const scales = <double>[1, 2];

  setUpAll(() async {
    // Before `setupDependencyInjection()`: several mocks seed clock-relative
    // data in instance-field initialisers, which run at construction, and the
    // locator's fields are `late final`. `AppClock.freeze` directly rather than
    // `freezeClock`, which needs an `addTearDown` that `setUpAll` does not have.
    AppClock.freeze(kFixedNow);
    await initializeDateFormatting('fr_FR', null);
    // **The gate measures text, so it has to measure the REAL typeface.** With
    // nothing loaded, `flutter_test` draws every glyph as a square of the font
    // size: « Semaine », « À venir » and « Annulés » all come out 98.7dp, and
    // « Aujourd'hui » comes out 155.1dp against Roboto's 72.2. The first run of
    // this file used that fallback and reported three tab labels as clipped
    // that fit with room to spare. See test/support/fonts.dart.
    await loadRealFonts();
    _seedPrefs();
    stubSecureStorage(); // else the session read throws, ON SCREEN
    setupDependencyInjection();
  });

  tearDownAll(AppClock.restore);

  setUp(() {
    freezeClock(kFixedNow);
    // Re-seeded per test as well: `HomeScreen` writes its selected commune
    // back through `SharedPreferences`, and the favourites below are read from
    // the same store — one screen's write is the next test's fixture otherwise.
    _seedPrefs();
  });

  for (final width in widths) {
    for (final scale in scales) {
      final at = '${width.toInt()}dp × ${scale.toInt()}× text';

      // ---- the two OTP screens ------------------------------------------
      //
      // Six 50dp boxes with 4dp gutters inside a 24dp page padding need 388dp,
      // and the padding is symmetric — so the row wants 388 + 48 = 436 and gets
      // the screen width. It is the cleanest arithmetic overflow in the app, and
      // it is invisible at 390 by 2dp of luck.
      //
      // Neither screen is routed today (`app_router.dart` declares no
      // `/verify-otp`), so this is the PROOF case rather than the headline —
      // recorded as such in the spec, because a gate justified by a story that
      // does not happen is worse than no gate.

      testWidgets('the consumer OTP screen fits $at', (tester) async {
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          home: OtpVerifyScreen(phoneNumber: kConsumerPhone),
          rounds: 1,
        );

        expect(
          find.byType(TextField),
          findsNWidgets(6),
          reason: 'C: the six-box code row is the subject — without it this '
              'test is about an empty Scaffold',
        );
        _expectOtpRowFitsTheFloor(tester, width: width, at: at);
        expectNoUndeclaredTruncation(tester,
            context: 'the consumer OTP at $at');
        expect(tester.takeException(), isNull, reason: 'A: $at');

        await _disposeTimers(tester);
      });

      testWidgets('the pro OTP screen fits $at', (tester) async {
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          home: const ProOtpVerifyScreen(phoneNumber: kConsumerPhone),
          rounds: 1,
        );

        expect(find.byType(TextField), findsNWidgets(6), reason: 'C');
        _expectOtpRowFitsTheFloor(tester, width: width, at: at);
        expectNoUndeclaredTruncation(tester, context: 'the pro OTP at $at');
        expect(tester.takeException(), isNull, reason: 'A: $at');

        await _disposeTimers(tester);
      });

      // ---- the pro earnings bar -----------------------------------------
      // (the OTP box's §13.3 growth assertion is outside these loops — see the
      // bottom of the file, and the note there about why looping is legal in
      // that one test and nowhere else.)
      //
      // Four tabs — « Aujourd'hui » « Semaine » « Mois » « Tout » — in a
      // non-scrollable TabBar, so each gets width / 4. « Aujourd'hui » is the
      // long one, and A10 already PHOTOGRAPHED it clipped at 390
      // (`pro_earnings.png`, §21 row 40). A `Tab` is `softWrap: false` with
      // `overflow: fade` (`tabs.dart:183`), which is why assertion A is silent
      // here and B is not.

      testWidgets('the pro earnings tabs fit $at', (tester) async {
        final auth = await signInPro(tester);
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          providers: [
            ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
            ChangeNotifierProvider(create: (_) => ProEarningsProvider()),
          ],
          home: const EarningsScreen(),
        );

        expect(find.text('Total'), findsOneWidget, reason: 'C');
        expect(
          find.text('Aucune transaction'),
          findsNothing,
          reason: 'C: the salon has takings — an empty ledger here means the '
              'load never landed, and the tabs would be all this measured',
        );
        expectNoUndeclaredTruncation(tester, context: 'pro earnings at $at');
        expect(tester.takeException(), isNull, reason: 'A: $at');
      });

      // ---- the pro appointment list -------------------------------------
      //
      // The same four-tab shape, one screen over, plus the two taps that make
      // it exist at all. See [_openProList].

      testWidgets('the pro appointment tabs fit $at', (tester) async {
        final auth = await signInPro(tester);
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          providers: [
            ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
            ChangeNotifierProvider(create: (_) => ProAppointmentProvider()),
          ],
          home: const AppointmentListScreen(),
        );
        await _openProList(tester);

        expectNoUndeclaredTruncation(
          tester,
          context: 'the pro appointment list at $at',
        );
        expect(tester.takeException(), isNull, reason: 'A: $at');
      });

      // ---- the consumer bookings ----------------------------------------
      //
      // Three tabs and a four-item BottomNavigationBar. Signed IN, because
      // signed out this screen is not this screen: its post-frame callback
      // raises a snackbar and `context.go('/login')`
      // (`my_bookings_screen.dart:36-47`).

      testWidgets('the consumer bookings fit $at', (tester) async {
        final auth = await signInConsumer(tester);
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider(create: (_) => AppointmentProvider()),
            ChangeNotifierProvider(create: (_) => ProviderProvider()),
          ],
          home: const MyBookingsScreen(),
        );

        expect(
          find.text('Aucun rendez-vous'),
          findsNothing,
          reason: 'C: user1 has a confirmed booking at now + 2d and a pending '
              'one at now + 5d — an empty « À venir » means the session or the '
              'load did not land',
        );
        expectNoUndeclaredTruncation(
          tester,
          context: 'consumer bookings at $at',
        );
        expect(tester.takeException(), isNull, reason: 'A: $at');
      });

      // ---- the consumer home --------------------------------------------
      //
      // Two `spaceBetween` rows pairing a `titleLarge` heading with a
      // `TextButton`: « Derniers rendez-vous » / « Voir tout » (`:259`) and
      // « Mes favoris » / « Voir la carte » (`:352`). Neither can shrink and
      // neither wraps, so at 2× they are an arithmetic overflow.
      //
      // **Both are behind `isAuthenticated`**, which is why the signed-out
      // golden never saw them, and why this one signs in and seeds two
      // favourites into the prefs the mock reads.

      testWidgets('the consumer home fits $at', (tester) async {
        final auth = await signInConsumer(tester);
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider(create: (_) => ProviderProvider()),
            ChangeNotifierProvider(create: (_) => AppointmentProvider()),
            ChangeNotifierProvider(create: (_) => FavoritesProvider()),
          ],
          home: const HomeScreen(),
          rounds: 5,
        );

        expect(
          find.text('Derniers rendez-vous'),
          findsOneWidget,
          reason: 'C: the heading this slice is about — it is behind '
              'isAuthenticated, so a signed-out pump measures nothing',
        );
        expect(find.text('Mes favoris'), findsOneWidget, reason: 'C');
        expectNoUndeclaredTruncation(tester, context: 'consumer home at $at');
        expect(tester.takeException(), isNull, reason: 'A: $at');
      });

      // ---- the pro reviews ----------------------------------------------
      //
      // The summary card is a `Row` of [rating column] + `Spacer` + [five
      // distribution rows], and each distribution row holds a HARD-CODED
      // `SizedBox(width: 100)` progress bar (`reviews_screen.dart:163`). The
      // text on both sides of it grows with the scale; the bar does not.

      testWidgets('the pro reviews summary fits $at', (tester) async {
        final auth = await signInPro(tester);
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          providers: [
            ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
            ChangeNotifierProvider(create: (_) => ProReviewsProvider()),
          ],
          home: const ReviewsScreen(),
        );

        expect(
          find.text('Aucun avis'),
          findsNothing,
          reason: 'C: provider1 has three seeded reviews — the empty state '
              'has no summary card, which is the whole subject',
        );
        expectNoUndeclaredTruncation(tester, context: 'pro reviews at $at');
        expect(tester.takeException(), isNull, reason: 'A: $at');
      });

      // ---- the consent sentence -----------------------------------------
      //
      // The one COMPONENT here, and the only open question in the set: §21
      // row 49 records that this `Wrap` costs four lines at 390 and asks what
      // it does at 360 × 2. A `Wrap` is supposed to survive that. **Green is
      // the answer being recorded, not a failure to find a bug.**

      // ---- the consent sentence -----------------------------------------
      testWidgets('the legal consent sentence fits $at', (tester) async {
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(AppTheme.spacingL),
              child: Center(child: LegalConsentText()),
            ),
          ),
          rounds: 0,
        );

        expect(find.byType(LegalConsentText), findsOneWidget, reason: 'C');
        expectNoUndeclaredTruncation(tester, context: 'legal consent at $at');
        expect(tester.takeException(), isNull, reason: 'A: $at');
      });
    }
  }

  // ---- §13.3: the OTP box grows with the text scale ---------------------
  //
  // **This one loops inside a single test, and that does not contradict the
  // "do not collapse" rule above.** That rule is about `_overflowReportNeeded`,
  // which latches once per render object and so hides a SECOND pump's overflow.
  // This test never reads an overflow report — it reads `getRect`, and sizes are
  // whatever the tree currently says. Comparing two scales is the assertion, so
  // two pumps in one test is the only shape that can make it.
  //
  // It is the assertion that catches restoring `height: 64`. A fixed height
  // around text does not overflow; it CLIPS, silently. Measured at the moment it
  // was removed, the field wanted **66.0dp at 1×** and had 64 — so the row
  // shipped 2dp of clipping on every device — and **99.0dp at 2×**, clipping by
  // 35. Nothing in 825 tests had anything to say about it.
  testWidgets('the OTP box grows with the OS text scale (§13.3)',
      (tester) async {
    Future<double> boxHeightAt(double scale) async {
      await pumpAtWidth(
        tester,
        width: 360,
        scale: scale,
        home: OtpVerifyScreen(phoneNumber: kConsumerPhone),
        rounds: 1,
      );
      expect(find.byType(TextField), findsNWidgets(6), reason: 'C');
      final h = tester.getRect(find.byType(TextField).first).height;
      await _disposeTimers(tester);
      return h;
    }

    final atOne = await boxHeightAt(1);
    final atTwo = await boxHeightAt(2);

    expect(
      atTwo,
      greaterThan(atOne),
      reason: 'the box is ${atOne}dp at 1× and ${atTwo}dp at 2× — it did not '
          'grow, so the digits are being clipped by a fixed bound (§13.3). '
          'This is what `height: 64` did, and takeException cannot see it.',
    );
  });
}

/// The six OTP boxes are equal, legal, and exactly as wide as the arithmetic
/// says (§13.2, and A11 C3).
///
/// `takeException` proves nothing here. The row's failure modes after C3 are all
/// **silent**: a `margin` left inside an `Expanded` makes the four middle boxes
/// 46.67dp while the ends are 50.67; the page padding left at `spacingL` makes
/// all six 45.33. Neither overflows. Both are under §13.2's 48 floor, and both
/// look like a working row in a picture nobody takes.
///
/// The `TextField` fills its box exactly, so one finder is both the box and the
/// tap target. **Every index is measured** — a `.first` would have passed on the
/// margin bug, whose first box is the one that is fine.
void _expectOtpRowFitsTheFloor(
  WidgetTester tester, {
  required double width,
  required String at,
}) {
  final boxes = [
    for (var i = 0; i < 6; i++) tester.getRect(find.byType(TextField).at(i)),
  ];

  // `(W − 2×spacingM − 5×spacingS)/6`, spelled out rather than named, so the
  // test states the contract instead of re-deriving it from the widget.
  final expected = (width - 2 * 16 - 5 * 8) / 6;

  for (var i = 0; i < 6; i++) {
    expect(
      boxes[i].width,
      closeTo(expected, 0.01),
      reason: 'box $i is ${boxes[i].width}dp at $at, and the row promises '
          '$expected — (W − 2×spacingM − 5×spacingS)/6. A margin inside the '
          'Expanded is the usual cause: it is spent from the slot, so the four '
          'middle boxes shrink and the two ends do not.',
    );
    expect(
      boxes[i].width,
      greaterThanOrEqualTo(48),
      reason: 'box $i is ${boxes[i].width}dp wide at $at — §13.2 says every '
          'touch target is ≥48×48, and this one is typed into',
    );
    expect(
      boxes[i].height,
      greaterThanOrEqualTo(48),
      reason: 'box $i is ${boxes[i].height}dp tall at $at (§13.2)',
    );
  }

  // **This one cannot fire while the assertion above holds, and it is kept
  // anyway.** The row's total width is fixed, so pinning each box to
  // `(W − 2×spacingM − 5×spacingS)/6` pins the gaps by subtraction: every
  // mutation tried against it — dropping `spacing:`, moving the margin back
  // inside the `Expanded`, widening the page padding — reddens the arithmetic
  // first, at 54.67dp, 50.67dp and 45.33dp respectively.
  //
  // What it is here for is the configuration the arithmetic would ALSO accept:
  // a smaller `spacing:` paid for with a wider padding still lands every box on
  // 48 while putting the targets 4dp apart. That is §13.2's other sentence, and
  // it would otherwise be expressed nowhere.
  for (var i = 1; i < 6; i++) {
    expect(
      boxes[i].left - boxes[i - 1].right,
      greaterThanOrEqualTo(8 - 0.01),
      reason: 'boxes ${i - 1} and $i are '
          '${(boxes[i].left - boxes[i - 1].right).toStringAsFixed(2)}dp apart '
          'at $at — §13.2: "targets that are adjacent need ≥8px between them, '
          'or a fat finger hits the wrong one".',
    );
  }
}

/// The prefs two subjects read before they can render their subject.
///
/// `favorites_user1` is `MockFavoritesService`'s storage key
/// (`mock_favorites_service.dart:10`) — favourites are not in `MockData` at all,
/// they live in `SharedPreferences`, so a `HomeScreen` test that seeds nothing
/// renders no « Mes favoris » section and measures a heading that is not there.
void _seedPrefs() => SharedPreferences.setMockInitialValues({
      'favorites_user1': '["provider1","provider2"]',
    });

/// Unmounts the tree so the OTP resend cooldown stops.
///
/// Both OTP screens run `Timer.periodic(const Duration(seconds: 1))` for a full
/// minute. `flutter_test` fails any test that ends with a live timer, and no
/// number of pumps will drain sixty of them — the screen has to go away. This is
/// the same two-line ending `otp_autofill_test.dart:27` uses.
Future<void> _disposeTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// Reaches the four-tab bar on `AppointmentListScreen`, and proves it arrived.
///
/// **Two taps, and neither is optional.**
///
/// 1. `TabBarView` builds only the visible page, so the whole « Liste » column —
///    including the TabBar this test exists to measure — does not exist while
///    « Calendrier » is showing. An unbuilt widget cannot overflow, so a
///    one-tap version of this test would be green at every width.
/// 2. Landing on « Liste » runs `_loadAppointmentsForListTab(0)` = « Aujourd'hui »,
///    which loads the salon's day bounds — and `MockData` seeds `provider1` at
///    `now + 2d`, `now - 10d` and `now - 7d`, never today. So the first thing the
///    tab shows is « Aucun rendez-vous », and the rows never render. « Tous »
///    is the tab with data in it.
Future<void> _openProList(WidgetTester tester) async {
  await tester.tap(find.text('Liste'));
  // kTabScrollDuration is 300ms and the tab's own reload is another 300; three
  // 400ms rounds clear both with room to spare.
  await settleMocks(tester, rounds: 3);
  expect(
    find.byType(TabBar),
    findsNWidgets(2),
    reason: 'the « Liste » page never built — its TabBar is the subject, and '
        'a TabBarView does not build a page it is not showing',
  );

  await tester.tap(find.text('Tous'));
  // kTabScrollDuration is 300ms and the tab's own reload is another 300; three
  // 400ms rounds clear both with room to spare.
  await settleMocks(tester, rounds: 3);
  expect(
    find.byType(Card),
    findsWidgets,
    reason: '« Tous » is the tab that has rows; if this is empty the gate is '
        'measuring an empty state and will pass about nothing',
  );
}

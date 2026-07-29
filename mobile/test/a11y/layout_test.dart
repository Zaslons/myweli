import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_dashboard_provider.dart';
import 'package:myweli/providers/pro_earnings_provider.dart';
import 'package:myweli/providers/pro_reviews_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/appointments/my_bookings_screen.dart';
import 'package:myweli/screens/auth/otp_verify_screen.dart';
import 'package:myweli/screens/booking/booking_confirmation_screen.dart';
import 'package:myweli/screens/booking/booking_hub_screen.dart';
import 'package:myweli/screens/home/home_screen.dart';
import 'package:myweli/screens/notifications/notifications_screen.dart';
import 'package:myweli/screens/provider/appointments/appointment_list_screen.dart';
import 'package:myweli/screens/provider/auth/pro_otp_verify_screen.dart';
import 'package:myweli/screens/provider/dashboard/dashboard_screen.dart';
import 'package:myweli/screens/provider/earnings/earnings_screen.dart';
import 'package:myweli/screens/provider/reviews/reviews_screen.dart';
import 'package:myweli/screens/providers/provider_detail_screen.dart';
import 'package:myweli/screens/providers/provider_list_screen.dart';
import 'package:myweli/widgets/common/commune_pill.dart';
import 'package:myweli/widgets/common/legal_consent_text.dart';
import 'package:myweli/widgets/notifications/notification_tile.dart';
import 'package:myweli/widgets/provider/provider_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fonts.dart';
import '../support/frozen_clock.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';
import '../support/tab_flows.dart';
import '_a11y.dart';

/// **A width is not all widths** (docs/design/mobile-a11-width.md, SYSTEM.md §10).
///
/// §10 defines `compact` as a RANGE. It said "everything under 600dp, with no floor" when this gate was written; C6 gave it one, so it now reads 360–599 —
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
        expectNoLegibilityCrush(tester, context: 'the consumer OTP at $at');
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
        expectNoLegibilityCrush(tester, context: 'the pro OTP at $at');
        expectNoVerticalClip(tester, context: 'the pro OTP at $at');
        expect(tester.takeException(), isNull, reason: 'A: $at');

        await _disposeTimers(tester);
      });

      // ---- the pro earnings bar -----------------------------------------
      // (the OTP box's §13.3 growth assertion is outside these loops — see the
      // bottom of the file, and the note there about why looping is legal in
      // that one test and nowhere else.)
      //
      // Four tabs — « Aujourd'hui » « Semaine » « Mois » « Tout ». Until C4 this
      // was a non-scrollable TabBar, so each tab got width / 4 and the long
      // label was faded away inside its share: A10 PHOTOGRAPHED it clipped at
      // 390 (`pro_earnings.png`, §21 row 40). A `Tab` is `softWrap: false` with
      // `overflow: fade` (`tabs.dart:183`), which is why assertion A was silent
      // about it and B was not. C4 made the bar scrollable; these tests are what
      // keep it that way.

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

        await openEarningsAll(tester);
        expect(find.text('Total'), findsOneWidget, reason: 'C');
        expectNoUndeclaredTruncation(tester, context: 'pro earnings at $at');
        expectNoLegibilityCrush(tester, context: 'pro earnings at $at');
        expectNoVerticalClip(tester, context: 'pro earnings at $at');
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
        await openProList(tester);

        expectNoUndeclaredTruncation(
          tester,
          context: 'the pro appointment list at $at',
        );
        expectNoLegibilityCrush(
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
        // §13.3, A11 C8: the date rendered « 13/03/20 » / « 26 » at 2× until
        // the `Row` of two `Expanded`s became a `Wrap`. A date is one token.
        for (final d in ['13/03/2026', '16/03/2026']) {
          expectNoMidWordBreak(tester, d, at);
        }
        expectNoUndeclaredTruncation(
          tester,
          context: 'consumer bookings at $at',
        );
        expectNoLegibilityCrush(
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
        _expectHeadingIsWhole(tester, 'Derniers rendez-vous', at);
        _expectHeadingIsWhole(tester, 'Mes favoris', at);
        _expectActionIsTappable(tester, 'Voir tout', at);
        _expectActionIsTappable(tester, 'Voir la carte', at);
        // A13, §21 row 62 — **the story-card titles are CONTROL labels.** Each
        // card is `Semantics(button: true)` + `InkWell(onTap:)` and the title is
        // the control's accessible name (`announcement_stories.dart:133-137`),
        // so §13.3's "any control's label" already forbade the break. Row 62
        // filed both open items as "headings" and left them to a slice that
        // would decide whether a heading may break — one of them was never that
        // question.
        //
        // All three are named, not just the one C7 photographed: measured
        // against the SDK's Roboto, the 64dp unseen box loses `Week‑End` above
        // **1.20×**, `Nouveau` above 1.38× and `Dernière` above 1.43×. So a
        // 1.3× branch would arrive late, and replacing the U+2011 in
        // « Promo Week‑End » would fix one of three.
        //
        // The hyphen is U+2011 (NON-BREAKING) and `expectNoMidWordBreak` splits
        // on `\s+`, so `Week‑End` is correctly one 8-glyph token to the gate.
        for (final title in const [
          'Promo Week\u2011End',
          'Nouveau salon',
          'Dernière minute',
        ]) {
          expectNoMidWordBreak(tester, title, at);
        }
        expectNoUndeclaredTruncation(tester, context: 'consumer home at $at');
        expectNoLegibilityCrush(tester, context: 'consumer home at $at');
        expectNoVerticalClip(tester, context: 'consumer home at $at');
        expect(tester.takeException(), isNull, reason: 'A: $at');
      });

      // ---- the salon page ------------------------------------------------
      //
      // **A11 C5 added this subject, and it was never measured before.** The
      // screen carries SEVEN section headings through a private `_SectionCard`,
      // one of which pairs « Vos rendez-vous ici » with the same « Voir tout »
      // button the home screen overflows on — at `titleMedium` instead of
      // `titleLarge`, with a `Spacer` instead of `spaceBetween`, and with no
      // `Expanded` on the title either. Three copies of one layout, already
      // drifted apart, and only this one was outside every gate.

      testWidgets('the salon page fits $at', (tester) async {
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
          home: const ProviderDetailScreen(providerId: 'provider1'),
          rounds: 5,
        );

        expect(
          find.text('Vos rendez-vous ici'),
          findsOneWidget,
          reason: 'C: the heading with an action beside it — signed out this '
              'screen renders « Connectez-vous pour voir vos rendez-vous. » '
              'instead, and the subject would be missing',
        );
        _expectHeadingIsWhole(tester, 'Vos rendez-vous ici', at);
        // §13.3, A11 C8: « Appeler » is one word and a 1:2 split left it 81dp
        // against the ~105 it wants at 2×, so the button read « Appel » / « er ».
        expectNoMidWordBreak(tester, 'Appeler', at);
        // A13, §21 row 62's other open item — and the one that IS the heading
        // question the row deferred. §13.3 named "a salon name" as a permitted
        // mid-word break; A13 decides otherwise, because a salon's name is what
        // identifies the business and « Salon Ex / cellence » is not a name.
        //
        // The header gives it `W − 24 − 72 (logo) − 16 − 24` = **224dp at 360**
        // and `Excellence` wants **270.3 at 2×**, so it breaks above 1.66× /
        // 1.77× / 1.88× at the three widths — the ≈1.95× device photo is that
        // arithmetic, not a coincidence.
        expectNoMidWordBreak(tester, 'Salon Excellence', at);
        expectNoUndeclaredTruncation(tester, context: 'the salon page at $at');
        expectNoLegibilityCrush(tester, context: 'the salon page at $at');
        expectNoVerticalClip(tester, context: 'the salon page at $at');
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
        // The bar is about to become `Expanded`, and a flexed bar in a row that
        // wants more than it has is a bar of ZERO width — green on A, on B and
        // on C, and invisible to a user. Five of them, so measure all five.
        for (var i = 0; i < 5; i++) {
          expect(
            tester.getSize(find.byType(LinearProgressIndicator).at(i)).width,
            greaterThanOrEqualTo(24),
            reason: 'distribution bar $i has collapsed at $at — a rating '
                'histogram whose bars carry no length is a column of numbers',
          );
        }
        expectNoUndeclaredTruncation(tester, context: 'pro reviews at $at');
        expectNoLegibilityCrush(tester, context: 'pro reviews at $at');
        expectNoVerticalClip(tester, context: 'pro reviews at $at');
        expect(tester.takeException(), isNull, reason: 'A: $at');
      });

      // ---- the salon list ------------------------------------------------
      //
      // A12, and §21 row 68's finding #2 — **device-confirmed before it was
      // gated**: « RIGHT OVERFLOWED BY 122 PIXELS » on a 360×780pt iPhone at
      // ≈1.95×. The subject is the filter row, and the trap is that the pill
      // looks safe: `CommunePill` carries its own `Flexible` + ellipsis, and
      // none of it binds while the pill is a NON-flex child of that row.
      //
      // `commune_pill_test.dart` and `text_scale_test.dart` both pump the pill
      // in isolation at 360×2× and pass — because in isolation its `Flexible`
      // IS bounded. The defect lives in the composition, so the composition is
      // the subject.
      testWidgets('the salon list filter row fits $at', (tester) async {
        final auth = await signInConsumer(tester);
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          providers: [
            ChangeNotifierProvider(create: (_) => ProviderProvider()),
            // `ProviderCard` reads both — the heart is per-user.
            ChangeNotifierProvider(create: (_) => FavoritesProvider()),
            ChangeNotifierProvider.value(value: auth),
          ],
          home: const ProviderListScreen(),
          rounds: 5,
        );

        expect(
          find.byType(CommunePill),
          findsOneWidget,
          reason: 'C: the pill is the subject',
        );
        // **A POSITIVE guard, and the adversarial review is why.** This was
        // `find.text('Aucun salon')` — a string `ProviderListScreen` cannot
        // render (its empty state says « Aucun salon trouvé »; the bare form
        // exists only in `admin_providers_screen.dart`), so it passed in all
        // four states. Correcting the string closes the EMPTY hole and not the
        // LOADING one, which is the state this guard's own reason names: while
        // the provider is still loading there is no count label and no empty
        // state, and a negative guard is green about a half-built row. Only
        // asserting the cards are there bites in every degenerate state.
        expect(
          find.byType(ProviderCard),
          findsWidgets,
          reason: 'C: no salon has loaded, so the count label — half of what '
              'overflows — is not built and the row cannot overflow',
        );
        expectNoUndeclaredTruncation(tester, context: 'salon list at $at');
        expectNoLegibilityCrush(tester, context: 'salon list at $at');
        expectNoVerticalClip(tester, context: 'salon list at $at');
        expect(tester.takeException(), isNull, reason: 'A: $at');
      });

      // ---- the salon list, GRID -------------------------------------------
      //
      // The same screen behind a toggle, and it needs its own subject because
      // **the subject above cannot reach it**: `_isGrid` starts `false`, so
      // every assertion in this file measured the list branch and A12's grid
      // fix was never once executed by a test. The device found the miss —
      // « BOTTOM OVERFLOWED BY 55 PIXELS » on both cards at ≈1.95×, *after*
      // `ProviderCard.gridHeight` shipped.
      //
      // The mechanism is two formulas in one file that disagree.
      // `gridHeight` is `142 + 68 × scale`, derived from the COMPACT image
      // floor; `_buildGridCard` decides compact with `maxH < 260`, a raw dp
      // number. Above ≈1.74× the bound crosses 260, so the card draws the
      // 180dp ROOMY image inside a box measured for the 110dp compact one.
      // A11's lesson, one layer in: a constant that gates a text-dependent
      // branch has to move with the text too.
      testWidgets('the salon list grid fits $at', (tester) async {
        final auth = await signInConsumer(tester);
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          providers: [
            ChangeNotifierProvider(create: (_) => ProviderProvider()),
            ChangeNotifierProvider(create: (_) => FavoritesProvider()),
            ChangeNotifierProvider.value(value: auth),
          ],
          home: const ProviderListScreen(),
          rounds: 5,
        );

        await tester.tap(find.byTooltip('Afficher en grille'));
        await settleMocks(tester, rounds: 3);

        // C — without this the test is green about the list it was already
        // measuring, which is exactly the failure being fixed.
        expect(
          find.byType(GridView),
          findsOneWidget,
          reason: 'C: the toggle did not switch to the grid',
        );
        expect(
          find.byType(ProviderCard),
          findsWidgets,
          reason: 'C: no card is in the grid to measure',
        );
        expectNoUndeclaredTruncation(tester, context: 'salon grid at $at');
        expectNoLegibilityCrush(tester, context: 'salon grid at $at');
        expectNoVerticalClip(tester, context: 'salon grid at $at');
        expect(tester.takeException(), isNull, reason: 'A: $at');
      });

      // ---- the two booking screens ----------------------------------------
      //
      // A12 shipped `LabelValueRow` and then wrote, in its own spec, that the
      // component test "proves the widget and not the wiring" because neither
      // screen is a subject and "two of them need a booking in progress to
      // reach". **That justification is false** — `consumer_screens_golden_test`
      // already pumps `BookingHubScreen(providerId: 'provider1')` standalone,
      // and the confirmation screen takes plain ids and a `DateTime`. The
      // adversarial review caught it, and the cost of the wrong excuse was a
      // live defect on the screen immediately before payment.
      //
      // **provider2 and `service4`, deliberately.** « Tissage » is the only
      // seeded service with a `priceMax`, so it is the only one that renders
      // « À partir de 15 000 FCFA » — the price-RANGE string, which is what
      // makes the service row's unflexed price wide enough to starve the
      // flexed name beside it. Seeding provider1 would gate the narrow case
      // and pass.
      testWidgets('the booking hub fits $at', (tester) async {
        final auth = await signInConsumer(tester);
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          providers: [
            ChangeNotifierProvider(create: (_) => ProviderProvider()),
            ChangeNotifierProvider(create: (_) => AppointmentProvider()),
            ChangeNotifierProvider.value(value: auth),
          ],
          home: const BookingHubScreen(providerId: 'provider2'),
          rounds: 5,
        );

        expect(
          find.text('Total'),
          findsWidgets,
          reason: 'C: the pinned summary bar is the subject',
        );
        expectNoUndeclaredTruncation(tester, context: 'booking hub at $at');
        expectNoLegibilityCrush(tester, context: 'booking hub at $at');
        expect(tester.takeException(), isNull, reason: 'A: $at');
      });

      testWidgets('the booking confirmation fits $at', (tester) async {
        final auth = await signInConsumer(tester);
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          providers: [
            ChangeNotifierProvider(create: (_) => ProviderProvider()),
            ChangeNotifierProvider(create: (_) => AppointmentProvider()),
            ChangeNotifierProvider(create: (_) => LocalityProvider()),
            ChangeNotifierProvider.value(value: auth),
          ],
          home: BookingConfirmationScreen(
            providerId: 'provider2',
            serviceIds: const ['service4'],
            appointmentDateTime: kFixedNow.add(const Duration(days: 3)),
          ),
          rounds: 5,
        );

        expect(
          find.text('Tissage'),
          findsWidgets,
          reason: 'C: the service row is the subject, and it only renders '
              'once the provider has loaded',
        );
        expectNoUndeclaredTruncation(
          tester,
          context: 'booking confirmation at $at',
        );
        expectNoLegibilityCrush(
          tester,
          context: 'booking confirmation at $at',
        );
        expect(tester.takeException(), isNull, reason: 'A: $at');
      });

      // ---- the notification centre ---------------------------------------
      //
      // The thirteenth subject, and the one this file most owed. §21 row 68
      // named `NotificationTile`'s crushed title; A12 built
      // `expectNoLegibilityCrush` **for it** and cites it in the primitive's
      // own docstring; and then the slice fixed everything around it and never
      // made the screen a subject, so the register row was about to close over
      // a defect still shipping. The adversarial review caught that.
      //
      // The subject is the SCREEN, not the tile, for the `CommunePill` reason:
      // a tile pumped alone gets whatever width the fixture hands it, and the
      // crush is a fact about the 240dp row the list actually leaves it.
      testWidgets('the notification centre fits $at', (tester) async {
        final auth = await signInConsumer(tester);
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          providers: [
            ChangeNotifierProvider(create: (_) => NotificationsProvider()),
            ChangeNotifierProvider.value(value: auth),
          ],
          home: const NotificationsScreen(),
          rounds: 5,
        );

        // C — an empty feed would measure the padding around « Aucune
        // notification », which is §20's named vacuity and the exact trap two
        // other subjects in this file fell into.
        expect(
          find.byType(NotificationTile),
          findsWidgets,
          reason: 'C: no tile is on screen — this would measure an empty state',
        );
        expectNoUndeclaredTruncation(tester, context: 'notifications at $at');
        expectNoLegibilityCrush(tester, context: 'notifications at $at');
        expectNoVerticalClip(tester, context: 'notifications at $at');
        expect(tester.takeException(), isNull, reason: 'A: $at');
      });

      // ---- the pro dashboard --------------------------------------------
      //
      // A12, and the tenth subject. §21 row 68's finding #3, **device-confirmed
      // before it was ever gated**: on a 360×780pt iPhone at ≈1.95× the four
      // `_StatCard`s show Flutter's striped banner at 16px / 2.6px / 16px, and
      // at ≈3.12× at 91px / 31px. The header row is
      // `Text(title, bodySmall)` beside `Icon(size: iconS)` with neither flexed
      // — and **an icon does not text-scale**, so at 2× a 20dp glyph sits in a
      // 126dp tile next to a label that has doubled.
      //
      // It is also where A12's grid fix gets tested rather than asserted: the
      // `childAspectRatio` pin proves the ratio is gone, and this proves the
      // tile actually grows.
      testWidgets('the pro dashboard fits $at', (tester) async {
        final auth = await signInPro(tester);
        await pumpAtWidth(
          tester,
          width: width,
          scale: scale,
          providers: [
            ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
            ChangeNotifierProvider(create: (_) => ProDashboardProvider()),
            ChangeNotifierProvider(create: (_) => NotificationsProvider()),
          ],
          home: const DashboardScreen(),
          rounds: 5,
        );

        expect(
          find.text('Opérations quotidiennes'),
          findsOneWidget,
          reason: 'C: the action grid is half the subject, and it renders '
              'below the stat cards — a screen that stopped at the header '
              'would measure neither',
        );
        // §13.3: an action card is a CONTROL, and a control's label may not
        // break inside a word. The golden at 360×2× read « Disponibil / ité »
        // once the tile started growing instead of clipping — which is the
        // defect the single-column branch above 1.3× exists to prevent, and
        // this is what holds it. By name, as §13.3 requires: a sweep would red
        // on the headings row 62 leaves open.
        // « Disponibilité » only, and both exclusions are deliberate.
        // « Rendez-vous » carries a HYPHEN, and breaking at one is legitimate
        // typography — `expectNoMidWordBreak` splits on whitespace, so it would
        // demand the whole hyphenated string on one line. It is also the stat
        // card's subtitle, so `find.text` matches twice and the helper takes a
        // single render object.
        expectNoMidWordBreak(tester, 'Disponibilité', 'the action grid at $at');
        expectNoUndeclaredTruncation(tester, context: 'pro dashboard at $at');
        expectNoLegibilityCrush(tester, context: 'pro dashboard at $at');
        expectNoVerticalClip(tester, context: 'pro dashboard at $at');
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
        expectNoLegibilityCrush(tester, context: 'legal consent at $at');
        expectNoVerticalClip(tester, context: 'legal consent at $at');
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

/// A section heading is WHOLE — not truncated, not squeezed (§13.3, A11 C5).
///
/// **This exists because the truncation walk cannot see the obvious wrong fix.**
/// `expectNoUndeclaredTruncation` skips any paragraph that declares
/// `TextOverflow.ellipsis`, by design — a declared ellipsis is §13.3-legal. So
/// adding `maxLines: 1, overflow: TextOverflow.ellipsis` to « Derniers
/// rendez-vous » turns every red in this file green **while shipping
/// « Derniers rendez… » to the user**, and nothing else here would object. C's
/// `find.text` would not either: it matches on the widget's string, not on what
/// was painted.
///
/// A heading may wrap. A heading may not be cut.
void _expectHeadingIsWhole(WidgetTester tester, String text, String at) {
  final p = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.text(text), matching: find.byType(RichText)),
  );
  expect(
    p.overflow,
    isNot(TextOverflow.ellipsis),
    reason:
        '« $text » declares an ellipsis at $at. That is legal for body copy '
        'and wrong for a section heading — and it is the change that makes this '
        'file green without making the screen right.',
  );
  expect(
    p.didExceedMaxLines,
    isFalse,
    reason: '« $text » is cut off at $at — it wanted more lines than '
        '${p.maxLines} and did not get them',
  );
}

/// A heading's action is still something a finger can hit (§13.2).
///
/// The other way to make the arithmetic work is to shrink the action until it
/// fits — « Voir tout » demoted to a 24dp glyph. That is green on every other
/// assertion in this file.
void _expectActionIsTappable(WidgetTester tester, String label, String at) {
  final size = tester.getSize(find.ancestor(
    of: find.text(label),
    matching: find.byType(TextButton),
  ));
  expect(
    size.width >= 48 && size.height >= 48,
    isTrue,
    reason: '« $label » is ${size.width}×${size.height} at $at — §13.2 says '
        'every touch target is ≥48×48',
  );
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
      // The pro dashboard offers push on its FIRST visit
      // (`push_registration.dart`), and a modal sheet over the subject measures
      // the sheet. A12 added the dashboard as a subject; this makes it the
      // second visit.
      'myweli_push_asked': true,
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

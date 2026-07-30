import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/core/utils/salon_time.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/providers/pro_artist_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_dashboard_provider.dart';
import 'package:myweli/providers/pro_deposit_settings_provider.dart';
import 'package:myweli/providers/pro_earnings_provider.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/providers/pro_reviews_provider.dart';
import 'package:myweli/providers/pro_subscription_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/appointments/appointment_list_screen.dart';
import 'package:myweli/screens/provider/auth/pro_login_screen.dart';
import 'package:myweli/screens/provider/dashboard/dashboard_screen.dart';
import 'package:myweli/screens/provider/earnings/earnings_screen.dart';
import 'package:myweli/screens/provider/journal/pro_journal_screen.dart';
import 'package:myweli/screens/provider/reviews/reviews_screen.dart';
import 'package:myweli/screens/provider/settings/deposit_settings_screen.dart';
import 'package:myweli/screens/provider/team/team_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:myweli/services/mock/mock_notification_service.dart';
import 'package:myweli/services/mock/mock_pro_artist_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_review_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/golden.dart';
import '../support/tab_flows.dart';

/// The pro app, under the real theme (docs/design/SYSTEM.md §20).
///
/// ## The dashboard and the journal ARE here now (A10)
///
/// This header used to explain why they could not be. The reason was true — both
/// read the wall clock on a render path, so a golden of either would have been
/// "a picture of the day it was taken: green on Tuesday, red on Wednesday" — and
/// it was copied verbatim into SYSTEM.md §21 row 23, where **two of its three
/// specifics turned out to be wrong**:
///
///   · there is no `MockProService.getDashboard()`; it is
///     `getDashboardStats(String providerId)`;
///   · `weekday` reaches exactly one value, `weekRevenue`, and **no screen
///     renders it**. The card the old text describes does not exist. The
///     dashboard's real flake was monthly and rare: an appointment seeded at
///     `now + 2d` falls into the NEXT month on the last two days of one, and
///     `monthRevenue` drops to zero;
///   · the journal's header does *not* print today's date — on the default path
///     `isToday` is always true, so it stably reads « Aujourd'hui ». The flake
///     was the **week strip**: seven pills printing `${d.day}`, all seven moving
///     daily, with the selection sliding one slot right and wrapping on Monday.
///
/// The row was also a large undercount — `earnings_screen` buckets by a
/// Monday-anchored weekday, which is what the row's description actually fits,
/// and it is the third picture below.
///
/// **What makes these three photographable** is `core/utils/app_clock.dart`: one
/// function pointer, frozen here at [kFixedNow] (Wed 11 March 2026, 10:30 UTC),
/// which every render-path clock read now goes through — including
/// `MockData`'s seeds, which `freezeClock` re-generates so that a frozen clock
/// cannot be paired with stale fixtures.
///
/// **The proof these are not just pictures of 11 March** is not in this file:
/// each baseline was generated twice, under two different frozen instants, and
/// the bytes compared. See docs/design/mobile-a10-clock.md.
///
/// DI note: this file HAND-ASSIGNS its services and never calls
/// `setupDependencyInjection()` — the locator's fields are `late final`, so it is
/// one or the other, and only hand-assignment lets [_FixedRoster] in.
void main() {
  group('goldens', () {
    setUpAll(() async {
      // **The freeze comes FIRST, before any service is constructed.** Several
      // mocks seed clock-relative data in instance-field initialisers, which run
      // at construction — and the locator's fields are `late final`, assignable
      // once, so a `setUp` cannot replace them afterwards (it throws
      // `Field ... has already been initialized`, which is how this was found).
      // `AppClock.freeze` directly rather than `freezeClock`, because
      // `addTearDown` does not exist in `setUpAll`; `tearDownAll` below undoes it.
      AppClock.freeze(kFixedNow);
      await initializeDateFormatting('fr_FR', null);
      // `myweli_push_asked`: PushRegistration's persisted "don't nag" flag
      // (core/push/push_registration.dart:26). Without it the dashboard's
      // first-visit push sheet slides up OVER the picture and the golden
      // photographs a modal on a dimmed screen — which is exactly what the
      // first generated baseline showed, and what the comment claiming
      // "no sheet opens" asserted without checking.
      SharedPreferences.setMockInitialValues({'myweli_push_asked': true});
      stubSecureStorage();

      serviceLocator.authService = MockAuthService();
      serviceLocator.proService = MockProService();
      serviceLocator.proTeamService = _FixedRoster();
      serviceLocator.proArtistService = MockProArtistService();
      serviceLocator.localityService = MockLocalityService();
      // A11 C7: `ProReviewsProvider` reads `serviceLocator.reviewService` in a
      // non-`late` field initialiser, so it throws at CONSTRUCTION — this file
      // hand-assigns rather than calling `setupDependencyInjection()` (the
      // locator's fields are `late final`, so it is one or the other), and a
      // service nobody had needed yet was simply absent.
      serviceLocator.reviewService = MockReviewService();
      // The dashboard's bell. `_items = _seed()` is a non-`late` instance field,
      // so it is generated HERE, at construction — which is why the freeze above
      // has to precede it. The first version assigned this before any freeze and
      // claimed in a comment that the seed was "generated when
      // `NotificationsProvider` builds it — after the freeze, which is why
      // « il y a 2 heures » is a fixed string in the picture". Both halves were
      // wrong: the provider receives the already-seeded singleton, and that
      // string is not in `pro_dashboard.png` at all — the bell renders a badge,
      // and the relative timestamps live on a screen this file does not
      // photograph. The picture was stable because the unread COUNT happens to be
      // clock-independent. Luck, of exactly the kind row 39 is about.
      serviceLocator.proNotificationService = MockNotificationService();
      // The dashboard offers push on its FIRST visit, from a post-frame
      // callback in `initState` — so the locator field is read before a single
      // pixel is laid out, and an unassigned `late final` throws there rather
      // than in the picture. The sheet itself is suppressed by the
      // `myweli_push_asked` pref above, not by anything here.
      serviceLocator.proPushRegistration = PushRegistration(
        push: MockPushNotificationService(),
        devices: MockDeviceRegistrationService(),
      );
      // A PAID offer with FIXED dates — a trial would print a countdown, and a
      // countdown is a clock in the picture.
      serviceLocator.subscriptionService = MockSubscriptionService(
        initial: SalonSubscription(
          tier: SalonTier.business,
          status: SalonOfferStatus.paid,
          trialEndsAt: DateTime.utc(2026, 1, 1),
          graceEndsAt: DateTime.utc(2026, 1, 8),
          seats: const SalonSeats(cap: 15, used: 6),
        ),
      );

      await loadRealFonts();
    });

    // Per test, not `setUpAll`: `freezeClock` wires `addTearDown`, which only
    // exists inside a test or a `setUp`. It also re-seeds `MockData`, so each
    // picture is taken against fixtures generated FROM the frozen instant — the
    // half that is easy to forget, and that looks exactly like a working freeze
    // when it is missing.
    tearDownAll(AppClock.restore);

    setUp(() {
      freezeClock(kFixedNow);
      // **Re-built AFTER the freeze, and the comment this replaces was wrong on
      // both of its claims.** It said the bell's seed is an instance field
      // "generated when `NotificationsProvider` builds it — after the freeze,
      // which is why « il y a 2 heures » is a fixed string in the picture".
      // `_items = _seed()` is a non-`late` instance field, so it runs at
      // CONSTRUCTION — which was in `setUpAll`, before any freeze — and the
      // provider receives the already-seeded singleton rather than building it.
      // And « il y a 2 heures » is not in `pro_dashboard.png` at all: the bell
      // renders a badge, and the relative timestamps live on a screen this file
      // does not photograph. The picture was stable because the unread COUNT is
      // clock-independent — luck, of exactly the kind row 39 is about.
    });

    testWidgets('the team roster', (tester) async {
      await _pumpPro(
        tester,
        const TeamScreen(),
        extra: [
          ChangeNotifierProvider(create: (_) => ProTeamProvider()),
          ChangeNotifierProvider(create: (_) => ProArtistProvider()),
          ChangeNotifierProvider(create: (_) => ProSubscriptionProvider()),
        ],
        size: const Size(390, 1000),
      );
      await expectGolden(tester, 'pro_team');
    });

    testWidgets('the deposit policy form', (tester) async {
      await _pumpPro(
        tester,
        const DepositSettingsScreen(providerId: 'provider1'),
        extra: [
          ChangeNotifierProvider(create: (_) => ProDepositSettingsProvider()),
          ChangeNotifierProvider(create: (_) => LocalityProvider()),
        ],
        size: const Size(390, 1000),
      );
      await expectGolden(tester, 'pro_deposit_settings');
    });

    // ---- A10: the three that could not be photographed --------------------

    testWidgets('the dashboard', (tester) async {
      await _pumpPro(
        tester,
        const DashboardScreen(),
        extra: [
          ChangeNotifierProvider(create: (_) => ProDashboardProvider()),
          ChangeNotifierProvider(
            create: (_) => NotificationsProvider(
              service: serviceLocator.proNotificationService,
            ),
          ),
        ],
        size: const Size(390, 1400),
      );
      await expectGolden(tester, 'pro_dashboard');
    });

    testWidgets('the journal', (tester) async {
      await _pumpPro(
        tester,
        const ProJournalScreen(),
        extra: [ChangeNotifierProvider(create: (_) => ProJournalProvider())],
        size: const Size(390, 1200),
        // `load` awaits one 300ms call and THEN `_prefetchWeekCounts` awaits six
        // more, one per week-strip pill. Three rounds photographs the strip
        // mid-prefetch — dots appearing one at a time is a picture of a race.
        rounds: 10,
      );
      await expectGolden(tester, 'pro_journal');
    });

    testWidgets('the journal, on a day that has appointments', (tester) async {
      // **The default view is the EMPTY state, and one picture of it is not a
      // photograph of this screen.** `MockData` seeds `provider1` at `now + 2d`,
      // `now - 10d` and `now - 7d` — never on today — so the journal a golden
      // catches on its default day says « Aucun rendez-vous ce jour » and pins
      // nothing but the strip and a placeholder. The timeline rows, the status
      // chips and the action row are most of the screen's tokens.
      //
      // Tapping into 13 March also pins the OTHER branch of `isToday`: the
      // header leaves « Aujourd'hui » for a formatted date. That branch is the
      // one §21 row 23 accused of flaking, wrongly — and it had never appeared
      // in any test.
      await _pumpPro(
        tester,
        const ProJournalScreen(),
        extra: [ChangeNotifierProvider(create: (_) => ProJournalProvider())],
        size: const Size(390, 1200),
        rounds: 10,
      );
      // DERIVED, and derived from the STRIP rather than from `now` — two
      // corrections, in that order. The first draft hard-coded '13' and passed,
      // until the determinism run moved the freeze to 22 September 2027, where
      // the strip reads 20–26 and there is no 13 to tap. The second draft used
      // `now + 2d`, which is only inside a Mon–Sun strip when `kFixedNow` falls
      // Mon–Fri: move it to a Saturday and the finder misses, or worse matches a
      // pill from an adjacent month. Anchoring on the strip's own Monday is
      // correct for any frozen instant, and the appointment `MockData` seeds at
      // `now + 2d` is what makes that day non-empty.
      final today = salonNow(now: kFixedNow);
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final target = monday.add(Duration(days: today.weekday - 1 + 2));
      await tester.tap(find.text('${target.day}'));
      await settleMocks(tester, rounds: 10);
      expect(find.text('Aujourd\u2019hui'), findsNothing,
          reason: 'the tap must have landed — if the strip did not move, this '
              'golden is a second copy of the one above');
      await expectGolden(tester, 'pro_journal_day');
    });

    // **Two pictures, and the first one is now honest.** Until A11 C4 this
    // screen's first load passed no date bounds at all while every tab tap
    // passed them, so the golden photographed « Aujourd'hui » listing every
    // transaction the salon had ever taken — including « dimanche 1 mars 2026 »
    // under a tab labelled today, with the clock frozen to 11 March. C4 made the
    // first load the selected tab's load, so this picture is what a salon
    // actually sees on opening: `MockData` seeds `provider1` at `now + 2d`,
    // `now - 10d` and `now - 7d` — never today — so « Aujourd'hui » is empty.
    //
    // That is a real state and worth a baseline: it pins the shared `EmptyState`
    // that replaced a bare `Center(Text(…))` in the same commit. But one picture
    // of an empty state is not a photograph of a screen, which is why the second
    // one exists — the same argument, and the same shape, as `pro_journal_day`.
    testWidgets('the earnings buckets, on the day the salon opens it',
        (tester) async {
      await _pumpPro(
        tester,
        const EarningsScreen(),
        extra: [ChangeNotifierProvider(create: (_) => ProEarningsProvider())],
        size: const Size(390, 1200),
      );
      expect(
        find.text('Aucune transaction'),
        findsOneWidget,
        reason: 'the first load must be the SELECTED tab\'s load — if this '
            'shows rows, `initState` has drifted back to loading unbounded and '
            'the picture is of a bug',
      );
      await expectGolden(tester, 'pro_earnings');
    });

    testWidgets('the earnings buckets, with takings in them', (tester) async {
      await _pumpPro(
        tester,
        const EarningsScreen(),
        extra: [ChangeNotifierProvider(create: (_) => ProEarningsProvider())],
        size: const Size(390, 1200),
      );
      await openEarningsAll(tester);
      await expectGolden(tester, 'pro_earnings_all');
    });

    // ---- A11 C7: the floor ---------------------------------------------
    //
    // Two subjects that no picture held at all. The appointment list is the
    // stronger of the two: `tabAlignment` is a property the width gate
    // provably cannot see — C4's own mutation table records that
    // `startOffset` reddens *"nothing in `flutter test`"* — so a golden is the
    // only instrument that measures it.

    testWidgets('the appointment list at the floor', (tester) async {
      await _pumpPro(
        tester,
        const AppointmentListScreen(),
        extra: [
          ChangeNotifierProvider(create: (_) => ProAppointmentProvider())
        ],
        size: const Size(360, 1200),
      );
      // No router: every `context.push` here is inside a callback a golden
      // never fires, which the width gate proves at six configurations.
      await openProList(tester);
      await expectGolden(tester, 'pro_appointment_list_w360');
    });

    testWidgets('the reviews summary at the floor', (tester) async {
      await _pumpPro(
        tester,
        const ReviewsScreen(),
        extra: [ChangeNotifierProvider(create: (_) => ProReviewsProvider())],
        size: const Size(360, 1200),
      );
      expect(
        find.text('Aucun avis'),
        findsNothing,
        reason: 'provider1 has three seeded reviews — the empty state has no '
            'summary card, and the histogram bar is the whole subject',
      );
      await expectGolden(tester, 'pro_reviews_w360');
    });

    // ---- A12: the dashboard at the floor, at 200% -----------------------
    //
    // The first picture of this screen anywhere but 390 × 1×, and it exists
    // because **regenerating every baseline after A12's dashboard fixes moved
    // nothing** — both are the identity at 390 × 1×, which is the definition of
    // the class §20.1's condition suffixes were introduced for.
    //
    // Two fixes in one frame: the `_StatCard` header, where an icon that does
    // not text-scale sat beside a label that doubles (19px over at 360×2×
    // before), and the action grid, whose `childAspectRatio: 1.1` froze the
    // tile at 143.6dp at every scale.
    testWidgets('the pro dashboard at the floor, at 200% text', (tester) async {
      await _pumpPro(
        tester,
        const DashboardScreen(),
        extra: [
          ChangeNotifierProvider(create: (_) => ProDashboardProvider()),
          // The service is passed EXPLICITLY, as the 1× dashboard golden does
          // twelve tests above: this file hand-assigns the locator rather than
          // calling `setupDependencyInjection()`, and `notificationService` is
          // not among the fields it assigns. The default constructor reads it
          // and a `late final` throws — which is what happened here first, and
          // it surfaced as a 99688px AppBar overflow, because the Consumer died
          // during build and left the bar without its actions.
          ChangeNotifierProvider(
            create: (_) => NotificationsProvider(
              service: serviceLocator.proNotificationService,
            ),
          ),
        ],
        // Tall: at 2× the stat cards and both grids run well past a phone, and
        // a golden photographs what is painted.
        size: const Size(360, 2600),
        scale: 2,
        rounds: 5,
      );
      expect(
        find.text('Opérations quotidiennes'),
        findsOneWidget,
        reason: 'the action grid is half the subject',
      );
      await expectGolden(tester, 'pro_dashboard_w360_x2');
    });

    // ---- A11 C8: the screen every pro sees first ------------------------
    //
    // There was no picture of the pro login at ANY width — the goldens hold a
    // `consumer_login.png` and nothing for the other app. That is where the
    // slice's last two defects lived, and both are invisible at 390 × 1×,
    // which is why regenerating every baseline after fixing them changed
    // nothing at all:
    //
    //   · « Pas encore de compte ? » + « S'inscrire » in a Row that could not
    //     wrap — 149px past a 360dp screen at 200% text.
    //   · « Continuer avec Google », whose label could not shrink.
    //
    // Signed OUT, so `_pumpPro` is the wrong helper: it exists to put a salon
    // owner into a session, and this is the screen before one.
    testWidgets('the pro login at the floor, at 200% text', (tester) async {
      goldenSurface(tester, size: const Size(360, 1400), scale: 2);
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ProAuthProvider(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: goldenTheme(),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('fr', 'FR')],
            locale: const Locale('fr', 'FR'),
            home: const ProLoginScreen(),
          ),
        ),
      );
      await settleMocks(tester, rounds: 3);

      // Both halves of the prompt, or the picture is of the wrong thing: a
      // signed-in session would render the dashboard and this golden would
      // quietly become a baseline for a screen it does not name.
      expect(find.text('Pas encore de compte ?'), findsOneWidget);
      expect(find.text('S\u2019inscrire'), findsOneWidget);

      await expectGolden(tester, 'pro_login_w360_x2');
    });
  }, skip: kGoldensSkip);
}

/// The roster's DATA is clock-stamped even though the screen isn't:
/// `MockProTeamService` sets `expiresAt: AppClock.now().add(7 days)`, and the
/// row prints it ("expire le lundi 20 juillet 2026").
///
/// **A10 makes this redundant and keeps it anyway** — with a correction to what
/// it was ever buying. With the clock frozen the seed is already deterministic,
/// so the override no longer prevents a daily flip; what it still pins is the
/// printed EXPIRY, far out in both directions, one invitation always pending and
/// one always expired.
///
/// It does NOT pin the row ORDER, and the claim that it made `pro_team.png`
/// independent of [kFixedNow] is measured to be false. The roster sorts on
/// `invitedAt` (`pro_team_provider.dart:223`), and two of the six members carry
/// clock-relative values while four are absolute (`mock_data.dart:695,730` vs
/// `:685,708,718`) — so moving the freeze across June 2026 reorders the list.
/// That is a real inconsistency in the seed, recorded in SYSTEM.md §21 rather
/// than papered over here: the two relative ones encode "invited 2 days ago,
/// still pending" and "invited 9 days ago, now expired", which are *inherently*
/// relative, and freezing them absolute would freeze the semantics with them.
///
/// The branch reads the seam rather than the wall clock, because a comparison
/// against an unfrozen clock inside a frozen test is the exact silent decoupling
/// `salon_time_pin_test` now pins.
class _FixedRoster extends MockProTeamService {
  @override
  Future<ApiResponse<List<TeamMember>>> getMembers() async {
    final base = await super.getMembers();
    final members = base.data;
    if (members == null) return base;
    return ApiResponse.success([
      for (final m in members)
        if (m.expiresAt == null)
          m
        else
          m.copyWith(
            expiresAt: m.expiresAt!.isAfter(AppClock.now())
                ? DateTime.utc(2099, 1, 1) // pending, forever
                : DateTime.utc(2000, 1, 1), // expired, forever
          ),
    ]);
  }
}

Future<void> _pumpPro(
  WidgetTester tester,
  Widget screen, {
  // SingleChildWidget, not ChangeNotifierProvider<ChangeNotifier>: the latter
  // pins the generic to ChangeNotifier, so every provider would register under
  // THAT type and the screen's `read<ProTeamProvider>()` would find nothing.
  required List<SingleChildWidget> extra,
  Size size = kGoldenPhone,
  double scale = 1,
  int rounds = 3,
}) async {
  goldenSurface(tester, size: size, scale: scale);

  // Sign the salon owner in for real BEFORE pumping: the provider session is
  // restored through async storage, which the fake clock can't drive — so it
  // happens under runAsync, the way dashboard_role_test does it.
  late final ProAuthProvider auth;
  await tester.runAsync(() async {
    final mockAuth = serviceLocator.authService as MockAuthService;
    await mockAuth.requestProviderEmailOtp('jean@salon-excellence.test');
    await mockAuth.verifyProviderEmailOtp(
      'jean@salon-excellence.test',
      MockAuthService.demoOtp,
    );
    auth = ProAuthProvider();
    for (var i = 0;
        i < 60 &&
            (auth.isLoading ||
                (auth.isAuthenticated && auth.membership == null));
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  });
  expect(auth.isAuthenticated, isTrue, reason: 'the pro session never landed');

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
        ...extra,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: goldenTheme(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('fr', 'FR')],
        locale: const Locale('fr', 'FR'),
        home: screen,
      ),
    ),
  );

  await settleMocks(tester, rounds: rounds);
}

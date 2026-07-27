import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/providers/pro_artist_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_dashboard_provider.dart';
import 'package:myweli/providers/pro_deposit_settings_provider.dart';
import 'package:myweli/providers/pro_earnings_provider.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/providers/pro_subscription_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/dashboard/dashboard_screen.dart';
import 'package:myweli/screens/provider/earnings/earnings_screen.dart';
import 'package:myweli/screens/provider/journal/pro_journal_screen.dart';
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
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/golden.dart';

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
      // A10: the dashboard's bell. Its seed is an INSTANCE field, so it is
      // generated when `NotificationsProvider` builds it — after the freeze,
      // which is why « il y a 2 heures » is a fixed string in the picture.
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

      await loadGoldenFonts();
    });

    // Per test, not `setUpAll`: `freezeClock` wires `addTearDown`, which only
    // exists inside a test or a `setUp`. It also re-seeds `MockData`, so each
    // picture is taken against fixtures generated FROM the frozen instant — the
    // half that is easy to forget, and that looks exactly like a working freeze
    // when it is missing.
    setUp(() => freezeClock(kFixedNow));

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
      await tester.tap(find.text('13'));
      await settleMocks(tester, rounds: 10);
      expect(find.text('Aujourd\u2019hui'), findsNothing,
          reason: 'the tap must have landed — if the strip did not move, this '
              'golden is a second copy of the one above');
      await expectGolden(tester, 'pro_journal_day');
    });

    testWidgets('the earnings buckets', (tester) async {
      await _pumpPro(
        tester,
        const EarningsScreen(),
        extra: [ChangeNotifierProvider(create: (_) => ProEarningsProvider())],
        size: const Size(390, 1200),
      );
      await expectGolden(tester, 'pro_earnings');
    });
  }, skip: kGoldensSkip);
}

/// The roster's DATA is clock-stamped even though the screen isn't:
/// `MockProTeamService` sets `expiresAt: AppClock.now().add(7 days)`, and the
/// row prints it ("expire le lundi 20 juillet 2026").
///
/// **A10 makes this redundant and keeps it anyway.** With the clock frozen the
/// seed is already deterministic, so the override no longer prevents a daily
/// flip. What it still buys is independence from [kFixedNow] itself: pinned FAR
/// out in both directions — one invitation always pending, one always expired —
/// `pro_team.png` does not churn if a later slice moves the frozen instant. The
/// branch reads the seam rather than the wall clock, because a comparison
/// against an unfrozen clock inside a frozen test is the exact silent
/// decoupling `salon_time_pin_test` now pins.
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
  int rounds = 3,
}) async {
  goldenSurface(tester, size: size);

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

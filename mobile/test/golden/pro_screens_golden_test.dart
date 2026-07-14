import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/providers/pro_artist_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_deposit_settings_provider.dart';
import 'package:myweli/providers/pro_subscription_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/settings/deposit_settings_screen.dart';
import 'package:myweli/screens/provider/team/team_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:myweli/services/mock/mock_pro_artist_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/golden.dart';

/// The pro app, under the real theme (docs/design/SYSTEM.md §20).
///
/// ## Why the dashboard and the journal are NOT here
///
/// Both take the time from the machine, and the codebase has no clock seam
/// (`package:clock` is unused):
///
///   · `ProJournalProvider._selectedDate = salonToday()` — the journal prints
///     TODAY's date into its header.
///   · `MockProService.getDashboard()` buckets by `DateTime.now().weekday`, so
///     its weekly stat cards change value depending on which day CI runs.
///
/// A golden of either would be a picture of the day it was taken: green on
/// Tuesday, red on Wednesday, failing every PR until someone regenerated it.
/// They are deliberately excluded, and the underlying defect — **the pro
/// surfaces cannot be pinned at the pixel level because they read the wall clock
/// directly** — is recorded in the violations register (SYSTEM.md §21) instead
/// of being papered over.
///
/// The two screens below are clock-FREE (verified: zero `DateTime.now()` /
/// `salonToday` / `DateFormat`), so they pin the pro surface's tokens honestly:
/// form controls, role chips, list rows, switches, the FAB.
///
/// DI note: this file HAND-ASSIGNS its services and never calls
/// `setupDependencyInjection()` — the locator's fields are `late final`, so it is
/// one or the other, and only hand-assignment lets [_FixedRoster] in.
void main() {
  group('goldens', () {
    setUpAll(() async {
      await initializeDateFormatting('fr_FR', null);
      SharedPreferences.setMockInitialValues({});
      stubSecureStorage();

      serviceLocator.authService = MockAuthService();
      serviceLocator.proService = MockProService();
      serviceLocator.proTeamService = _FixedRoster();
      serviceLocator.proArtistService = MockProArtistService();
      serviceLocator.localityService = MockLocalityService();
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
  }, skip: kGoldensSkip);
}

/// The roster's DATA is clock-stamped even though the screen isn't:
/// `MockProTeamService` sets `expiresAt: DateTime.now().add(7 days)`, and the
/// row prints it ("expire le lundi 20 juillet 2026") — a golden that would
/// change every single day.
///
/// So the dates are pinned FAR out, in both directions: one invitation that is
/// always pending and one that is always expired, whatever year it is when you
/// read this.
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
            expiresAt: m.expiresAt!.isAfter(DateTime.now())
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
        locale: const Locale('fr', 'FR'),
        home: screen,
      ),
    ),
  );

  await settleMocks(tester, rounds: 3);
}

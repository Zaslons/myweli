import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_revenue_provider.dart';
import 'package:myweli/screens/provider/earnings/revenue_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fonts.dart';
import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/revenue_fixtures.dart';
import '../support/revenue_service.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';
import '../support/surface.dart';
import '_a11y.dart';

/// The fold gate (A12) — a body that does not fit the screen it is on.
///
/// **Every other file in this directory pumps 1600dp of height**, and that is
/// deliberate: an overflow is reported from `paint`, so a row scrolled out of a
/// short viewport is a row those gates cannot see. It is also exactly why no
/// test in this repo has ever been able to see a VERTICAL overflow — 1600dp of
/// height means every `Column` fits.
///
/// This file is the opposite trade, and deliberately narrow. At [kFloorPhone]
/// only the first screenful is painted, so it can find one thing: a
/// **non-scrolling body that does not fit**.
///
/// ## Why the subject is a SCREEN and not `EmptyState`
///
/// §21 row 68's thirteenth finding is device-confirmed — `EmptyState` 3px over
/// at ≈1.95× on a 360×780pt iPhone. The obvious gate is the component at
/// `kFloorPhone`, and it is **green**: given a whole 780dp Scaffold body the
/// column fits with room to spare.
///
/// The 3px came from the HOST. On the earnings tab the empty state sits under
/// an app bar, a tab strip and a summary card, with roughly 389dp left — and
/// *that* is the box it does not fit. A component test cannot see it, which is
/// why four existing ones do not: `empty_state_test.dart` at 800×600×1×, and
/// `app_button_test.dart` at the right 360×2× but with no `description`, so the
/// tall branch never builds.
///
/// So the subject is the screen the device found it on, at the height the
/// device had.
///
/// {1×, 2×}, not 1.95×. The device maps `accessibility-large` to ≈1.95× and the
/// defect is 3px there; 2× is strictly worse, so 2× is red wherever 1.95× is,
/// and the suite keeps one scale vocabulary.
void main() {
  setUpAll(() async {
    AppClock.freeze(kFixedNow);
    await initializeDateFormatting('fr_FR', null);
    await loadRealFonts();
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    setupDependencyInjection();
  });
  tearDownAll(AppClock.restore);
  setUp(() => freezeClock(kFixedNow));

  // « Revenus » (pro-revenue-analytics.md §4.11): a salon with no completed
  // booking ever — the « Prévu » tile and the empty state under the period
  // bar — on the floor phone. The body is a list, so it may scroll; what it
  // must not do is overflow or clip on the way.
  for (final scale in [1.0, 2.0]) {
    testWidgets('« Revenus » with no revenue yet fits a phone at ${scale}x', (
      tester,
    ) async {
      final auth = await signInPro(tester);
      pinSurface(tester, size: kFloorPhone, scale: scale);
      // **The safe area is part of the phone** (the status bar and the home
      // indicator of a 360×780pt iPhone 13 mini).
      tester.view.padding = const FakeViewPadding(top: 50, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 50, bottom: 34);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      final service = FakeRevenueService()
        ..analytics = (_) => revenueAnalyticsJson(
          everCompleted: false,
          groups: [
            revenueGroup(
              current: revenueFigures(
                completedAmount: 0,
                completedCount: 0,
                averageTicket: null,
                noShowAmount: 0,
                noShowCount: 0,
                noShowRate: null,
              ),
              withPrevious: false,
              byArtist: [],
              byService: [],
              byChannel: [],
            ),
          ],
        );
      await pumpApp(
        tester,
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(
            create: (_) => ProRevenueProvider(service: service),
          ),
        ],
        theme: AppTheme.themeData(fontFamily: kRealFont),
        home: const RevenueScreen(),
      );
      await settleMocks(tester, rounds: 3);

      // C — the period bar is on screen (the empty state is below it).
      expect(find.text('Novembre 2026'), findsOneWidget, reason: 'C');
      expect(
        tester.takeException(),
        isNull,
        reason:
            '« Revenus » overflows a ${kFloorPhone.height.toInt()}dp '
            'phone at ${scale}x',
      );
      expectNoVerticalClip(tester, context: 'Revenus, empty, at ${scale}x');
    });
  }
}

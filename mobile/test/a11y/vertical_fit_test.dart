import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_earnings_provider.dart';
import 'package:myweli/screens/provider/earnings/earnings_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fonts.dart';
import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
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

  for (final scale in [1.0, 2.0]) {
    testWidgets('the pro earnings empty tab fits a phone at ${scale}x', (
      tester,
    ) async {
      final auth = await signInPro(tester);
      // `pumpAtWidth` would give this 1600dp of height, which is the whole
      // reason the defect has never been visible. Pin the real phone instead.
      pinSurface(tester, size: kFloorPhone, scale: scale);
      // **The safe area is part of the phone.** 780pt is the SCREEN; the
      // usable body is that minus the status bar and the home indicator, and
      // on the iPhone 13 mini that is 50 + 34. Without them this pumps ~84dp
      // more height than the device had, which is why the first version of
      // this test was green about a defect a device had already shown.
      tester.view.padding = const FakeViewPadding(top: 50, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 50, bottom: 34);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await pumpApp(
        tester,
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProEarningsProvider()),
        ],
        theme: AppTheme.themeData(fontFamily: kRealFont),
        home: const EarningsScreen(),
      );
      await settleMocks(tester, rounds: 3);

      // C — the empty state is the subject, so it must actually be on screen.
      // « Aujourd'hui » is the first tab and `MockData` seeds provider1 at
      // now+2d / now−10d / now−7d, never today, so this is the default view.
      expect(
        find.text('Aucune transaction'),
        findsOneWidget,
        reason: 'the empty state is not showing — this would measure a list',
      );

      expect(
        tester.takeException(),
        isNull,
        reason:
            'the empty state does not fit the space the earnings tab '
            'leaves it on a ${kFloorPhone.height.toInt()}dp phone at ${scale}x',
      );
      expectNoVerticalClip(tester, context: 'earnings empty tab at ${scale}x');
    });
  }
}

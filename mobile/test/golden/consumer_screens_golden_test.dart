import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/auth/login_screen.dart';
import 'package:myweli/screens/booking/booking_hub_screen.dart';
import 'package:myweli/screens/home/home_screen.dart';
import 'package:myweli/screens/providers/provider_detail_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/golden.dart';

/// The consumer app's four load-bearing screens, rendered under the REAL theme
/// (docs/design/SYSTEM.md §20).
///
/// The token sheets prove a token changed; these prove the PRODUCT still looks
/// right afterwards. `home` in particular is where the confirmed 200%-text-scale
/// break lives (`widgets/home/category_chips.dart:25`, register row 15) — A5 will
/// diff against this image.
///
/// DI note: these files call `setupDependencyInjection()` and NOTHING else. The
/// locator's fields are `late final` — assignable once per isolate — so a file
/// may either wire everything (this) or hand-assign a few services, never both.
void main() {
  group('goldens', () {
    setUpAll(() async {
      await initializeDateFormatting('fr_FR', null);
      SharedPreferences.setMockInitialValues({});
      stubSecureStorage(); // else the session read throws, ON SCREEN
      setupDependencyInjection(); // every service, all mocks
      await loadGoldenFonts();
    });

    testWidgets('the home screen', (tester) async {
      await _pumpScreen(tester, const HomeScreen());
      await expectGolden(tester, 'consumer_home');
    });

    testWidgets('the provider detail', (tester) async {
      await _pumpScreen(
        tester,
        const ProviderDetailScreen(providerId: 'provider1'),
        // The salon page is long; capture enough of it to be worth diffing.
        size: const Size(390, 1200),
      );
      await expectGolden(tester, 'consumer_provider_detail');
    });

    testWidgets('the booking hub', (tester) async {
      await _pumpScreen(
        tester,
        const BookingHubScreen(providerId: 'provider1'),
      );
      await expectGolden(tester, 'consumer_booking_hub');
    });

    testWidgets('the login screen', (tester) async {
      await _pumpScreen(tester, const LoginScreen());
      await expectGolden(tester, 'consumer_login');
    });
  }, skip: kGoldensSkip);
}

/// Every consumer screen sits under the same four ChangeNotifiers and a router
/// (several of them call `context.push`, so a bare MaterialApp would throw).
Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size size = kGoldenPhone,
  int rounds = 3,
}) async {
  goldenSurface(tester, size: size);

  // `AuthProvider` restores the session in its CONSTRUCTOR, and that read goes
  // through the session store — a real async hop that `pump()`'s fake clock
  // cannot drive. Build it under `runAsync` and wait for it to land, the way
  // dashboard_role_test does.
  //
  // This is not a nicety. Left unsettled, `auth.isLoading` stays true, the
  // login screen's CTA renders `isLoading: true` — i.e. the `BrandLoader`
  // Lottie — and the golden captures a button with NO LABEL, plus an animation
  // frame that is a flake waiting to happen.
  late final AuthProvider auth;
  await tester.runAsync(() async {
    auth = AuthProvider();
    for (var i = 0; i < 60 && auth.isLoading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  });
  expect(auth.isLoading, isFalse, reason: 'the session never settled');

  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (_, __) => screen)],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(create: (_) => ProviderProvider()),
        ChangeNotifierProvider(create: (_) => AppointmentProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: goldenTheme(),
        locale: const Locale('fr', 'FR'),
        routerConfig: router,
      ),
    ),
  );

  // The rest load through the mocks' `Future.delayed` (300ms), which the fake
  // clock CAN drive. pumpAndSettle would never return (the Lottie repeats
  // forever), so advance it by hand — [rounds] = the deepest sequential chain.
  await settleMocks(tester, rounds: rounds);
}

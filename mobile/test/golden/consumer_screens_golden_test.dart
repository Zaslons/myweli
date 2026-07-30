import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/appointments/my_bookings_screen.dart';
import 'package:myweli/screens/auth/login_screen.dart';
import 'package:myweli/screens/booking/booking_hub_screen.dart';
import 'package:myweli/screens/home/home_screen.dart';
import 'package:myweli/screens/providers/provider_detail_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/frozen_clock.dart';
import '../support/golden.dart';
import '../support/sign_in.dart';

/// The consumer app's four load-bearing screens, rendered under the REAL theme
/// (docs/design/SYSTEM.md §20).
///
/// The token sheets prove a token changed; these prove the PRODUCT still looks
/// right afterwards. `home` in particular is where the confirmed 200%-text-scale
/// break lives (`widgets/home/category_chips.dart:25`, register row 15) — A5 will
/// diff against this image.
///
/// **A10: frozen, and they were not.** `consumer_provider_detail` and
/// `consumer_booking_hub` both render clock-derived values
/// (`provider_detail_screen.dart:443`, `booking_hub_screen.dart:97,339,746-747`)
/// and were stable only **by luck** — `MockData` seeds at offsets from *now*, so
/// the relative comparisons happened to land the same way whenever CI ran. One
/// absolute date in the seed away from a daily failure.
///
/// A10's first draft left this file alone and then claimed in §20.1 that these
/// two were "stable by construction". They were not, and the two-instant
/// determinism proof was **vacuous for them**: a file that never reads
/// `kFixedNow` cannot change when `kFixedNow` moves, so their byte-identity
/// proved nothing — the exact failure mode §20.1 warns about one sentence
/// earlier. `freezeClock` makes the claim true.
///
/// DI note: these files call `setupDependencyInjection()` and NOTHING else. The
/// locator's fields are `late final` — assignable once per isolate — so a file
/// may either wire everything (this) or hand-assign a few services, never both.
void main() {
  group('goldens', () {
    setUpAll(() async {
      // Before `setupDependencyInjection()`: several mocks seed clock-relative
      // data in instance-field initialisers, which run at construction, and the
      // locator's fields are `late final` — assignable once, so no later `setUp`
      // can replace them. `AppClock.freeze` directly because `addTearDown` does
      // not exist in `setUpAll`; `tearDownAll` undoes it.
      AppClock.freeze(kFixedNow);
      await initializeDateFormatting('fr_FR', null);
      // `favorites_user1` is `MockFavoritesService`'s storage key — favourites
      // are not in `MockData` at all. Without it a signed-in home renders no
      // « Mes favoris » section and C7's picture is missing half its subject.
      SharedPreferences.setMockInitialValues({
        'favorites_user1': '["provider1","provider2"]',
      });
      stubSecureStorage(); // else the session read throws, ON SCREEN
      setupDependencyInjection(); // every service, all mocks
      await loadRealFonts();
    });

    tearDownAll(AppClock.restore);

    // And per test as well, for the `MockData` re-seed: the statics are shared
    // across the isolate, and a screen that mutates them would otherwise leave
    // the next picture reading its writes.
    setUp(() => freezeClock(kFixedNow));

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

    // ---- A11 C7: the floor, and the scale ------------------------------
    //
    // Five baselines at **360** — the modal Android device in Côte d'Ivoire, a
    // width no picture in this repo had ever rendered. Three are also its first
    // at **200% text**, which matters more than the width: four of A11's fixes
    // are the identity at 1×, so a 390×1× baseline is blind to them by
    // construction, and `tabAlignment` reddens nothing in `flutter test` at all.
    //
    // Not a survey of widths — the floor, once. `golden.dart` says which is
    // which and why the other 27 stay at 390.

    testWidgets('the home screen at the floor, at 200% text', (tester) async {
      await _pumpScreen(
        tester,
        const HomeScreen(),
        signedIn: true, // or neither heading exists — see `_pumpScreen`
        // Tall, because at 2× the content roughly doubles and « Mes favoris »
        // is the last section. A frame inherited from 1× photographs an AppBar.
        size: const Size(360, 3000),
        scale: 2,
        rounds: 5,
      );
      expect(
        find.text('Derniers rendez-vous'),
        findsOneWidget,
        reason: 'the heading C5 rewrote — behind isAuthenticated, which is why '
            'consumer_home.png contains zero A11 pixels',
      );
      expect(find.text('Mes favoris'), findsOneWidget);
      await expectGolden(tester, 'consumer_home_w360_x2');
    });

    testWidgets('the salon page at the floor, at 200% text', (tester) async {
      await _pumpScreen(
        tester,
        const ProviderDetailScreen(providerId: 'provider1'),
        signedIn: true,
        // Taller still: « Avis » is the 6th of 7 cards, and `review_tile`'s
        // wrapped verified badge lives inside it.
        size: const Size(360, 4200),
        scale: 2,
        rounds: 5,
      );
      expect(
        find.text('Vos rendez-vous ici'),
        findsOneWidget,
        reason: 'signed out this card renders the login prompt, and the third '
            'SectionHeading copy would not be in the picture',
      );
      await expectGolden(tester, 'consumer_provider_detail_w360_x2');
    });

    testWidgets('my bookings at the floor, at 200% text', (tester) async {
      await _pumpScreen(
        tester,
        const MyBookingsScreen(),
        // Signed out this screen is not this screen: its post-frame callback
        // raises a snackbar and `context.go('/login')`.
        signedIn: true,
        size: const Size(360, 2000),
        scale: 2,
      );
      expect(
        find.text('Aucun rendez-vous'),
        findsNothing,
        reason: 'user1 has a confirmed booking at now + 2d — an empty '
            '« À venir » means the session or the load did not land',
      );
      await expectGolden(tester, 'consumer_my_bookings_w360_x2');
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
  double scale = 1.0,
  // A11 C7. Every consumer golden was pumped SIGNED OUT, and two of them were
  // photographs of a logged-out fallback nobody noticed: `consumer_home.png`
  // hides both of `home_screen`'s section headings behind `isAuthenticated`
  // (`:236`, `:322`), and the salon page renders « Connectez-vous pour voir vos
  // rendez-vous. » instead of its appointments card. So the whole of C5's work
  // on those two screens produced **zero pixels** in the baseline.
  bool signedIn = false,
  int rounds = 3,
}) async {
  goldenSurface(tester, size: size, scale: scale);

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
  if (signedIn) {
    auth = await signInConsumer(tester);
  } else {
    await tester.runAsync(() async {
      auth = AuthProvider();
      for (var i = 0; i < 60 && auth.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });
    expect(auth.isLoading, isFalse, reason: 'the session never settled');
  }

  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (_, _) => screen)],
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
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('fr', 'FR')],
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

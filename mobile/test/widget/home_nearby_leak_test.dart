import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/router/app_router.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/home/home_screen.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/widgets/provider/provider_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/surface.dart';

/// docs/design/consumer-search.md §Today and §2.7 — the defect A4 fixes, as
/// a person met it: the home, the salon list and the map shared ONE list and
/// one category, so what was chosen on the list came back as the home's
/// « Près de vous », under its unchanged title.
///
/// Written against `main` before the fix (red there), with nothing but the
/// screens and the real `/providers` route.
void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    setupDependencyInjection(); // every service, all mocks
  });

  Future<GoRouter> pumpHome(WidgetTester tester) async {
    // Wide and tall: every « Près de vous » card built.
    pinSurface(tester, size: const Size(1400, 4000));
    late AuthProvider auth;
    await tester.runAsync(() async {
      auth = AuthProvider();
      for (var i = 0; i < 60 && auth.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/providers',
          builder: AppRouter.router.configuration.routes
              .whereType<GoRoute>()
              .firstWhere((r) => r.path == '/providers')
              .builder,
        ),
      ],
    );
    await tester.pumpWidget(
      wrapApp(
        routerConfig: router,
        providers: [
          ChangeNotifierProvider(create: (_) => ProviderProvider()),
          ChangeNotifierProvider(create: (_) => FavoritesProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => AppointmentProvider()),
        ],
      ),
    );
    await settleMocks(tester, rounds: 3);
    return router;
  }

  /// « Près de vous », in screen order: the home's only list cards (the
  /// carousels draw grid cards).
  List<String> nearby(WidgetTester tester) => [
    for (final c in tester.widgetList<ProviderCard>(find.byType(ProviderCard)))
      if (!c.isGrid) c.provider.id,
  ];

  testWidgets('« Barbier » on the list, then back: « Près de vous » still '
      'shows every salon', (tester) async {
    final router = await pumpHome(tester);
    final before = nearby(tester);
    expect(before, hasLength(MockData.providers.length));

    await tester.tap(find.text('Barbier'));
    await settleMocks(tester, rounds: 2);
    router.pop();
    await settleMocks(tester, rounds: 2);

    expect(nearby(tester), before);
  });

  testWidgets('« Disponible aujourd’hui » on the list does not narrow the '
      'home', (tester) async {
    // A Monday at 10:00 in Abidjan: two seeded salons are closed on Mondays,
    // so the filter narrows. On a day it narrows nothing, this would pass
    // against the defect.
    freezeClock(DateTime.utc(2026, 11, 23, 10));
    final router = await pumpHome(tester);
    final before = nearby(tester);
    expect(before, hasLength(MockData.providers.length));

    await tester.tap(find.text('Rechercher un salon…'));
    await settleMocks(tester, rounds: 2);
    await tester.tap(find.text('Disponible aujourd’hui'));
    await settleMocks(tester, rounds: 2);
    expect(
      nearby(tester).length,
      lessThan(before.length),
      reason: 'C: the filter narrowed the list',
    );
    router.pop();
    await settleMocks(tester, rounds: 2);

    expect(nearby(tester), before);
  });

  testWidgets('« Mieux notés » on the list does not reorder the home', (
    tester,
  ) async {
    final router = await pumpHome(tester);
    final before = nearby(tester);
    expect(before, hasLength(MockData.providers.length));

    await tester.tap(find.text('Tous'));
    await settleMocks(tester, rounds: 2);
    await tester.tap(find.text('Trier'));
    await settleMocks(tester);
    await tester.tap(find.text('Mieux notés'));
    await settleMocks(tester, rounds: 2);
    router.pop();
    await settleMocks(tester, rounds: 2);

    expect(nearby(tester), before);
  });
}

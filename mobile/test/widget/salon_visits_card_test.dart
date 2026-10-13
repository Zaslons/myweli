import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/providers/provider_detail_screen.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

/// « Vos rendez-vous ici » renders ONLY for a signed-in client with visits at
/// this salon — the web's `SalonVisitsCard` rule (parity 2.7). It used to show
/// « Connectez-vous pour voir vos rendez-vous. » to everyone signed out and
/// « Aucun rendez-vous dans ce salon. » to everyone without a visit
/// (docs/design/salon-rating-new-and-visits-card.md §2.3).
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage(); // else the session read throws
    setupDependencyInjection(); // every service, all mocks
  });

  Future<void> pump(WidgetTester tester, {required bool signedIn}) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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
    }
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const ProviderDetailScreen(providerId: 'provider1'),
        ),
      ],
    );
    await tester.pumpWidget(
      wrapApp(
        routerConfig: router,
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProviderProvider()),
          ChangeNotifierProvider(create: (_) => AppointmentProvider()),
          ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ],
      ),
    );
    await settleMocks(tester, rounds: 5);
  }

  testWidgets('signed out: no card, no sign-in prompt', (tester) async {
    await pump(tester, signedIn: false);
    expect(find.text('Services'), findsOneWidget, reason: 'the page loaded');
    expect(find.text('Vos rendez-vous ici'), findsNothing);
    expect(
      find.text('Connectez-vous pour voir vos rendez-vous.'),
      findsNothing,
    );
  });

  testWidgets('signed in with visits here: the card and « Voir tout »', (
    tester,
  ) async {
    expect(
      MockData.appointments.where((a) => a.providerId == 'provider1'),
      isNotEmpty,
      reason: 'the fixture this case depends on',
    );
    await pump(tester, signedIn: true);
    expect(find.text('Vos rendez-vous ici'), findsOneWidget);
    expect(find.text('Voir tout'), findsOneWidget);
  });

  // « Signed in, no visit here » lives in salon_visits_card_none_test.dart:
  // the mock appointment service copies `MockData.appointments` ONCE, when
  // the locator is built, so that case needs its own trimmed fixture.
}

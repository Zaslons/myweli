import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/revenue_analytics.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_revenue_provider.dart';
import 'package:myweli/screens/provider/earnings/revenue_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_revenue.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';
import '../support/surface.dart';

/// « Revenus » says what its figures count, and never that MyWeli saw a
/// payment (docs/design/pro-revenue-analytics.md §4.10, §13.2 — the old
/// screen's wording test, moved to the new screen's words).
///
/// « Réalisé » is completed bookings only, at the price shown at booking;
/// « Prévu » and « À clôturer » are apart. MyWeli never holds the money, so
/// nothing on the screen says « encaissé », « paiements reçus » or « chiffre
/// d’affaires » — the one « encaiss » allowed is the footnote's negation,
/// « MyWeli n’encaisse rien ».
///
/// The real mock world (MockRevenueWorld), every tab, read as rendered.
void main() {
  setUpAll(() async {
    AppClock.freeze(kFixedNow);
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    setupDependencyInjection();
  });
  tearDownAll(AppClock.restore);
  setUp(() => freezeClock(kFixedNow));

  Future<void> pump(WidgetTester tester, {ProServiceInterface? service}) async {
    final auth = await signInPro(tester);
    pinSurface(tester, size: const Size(390, 6000));
    await pumpApp(
      tester,
      providers: [
        ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
        ChangeNotifierProvider(
          create: (_) => ProRevenueProvider(service: service),
        ),
      ],
      home: const RevenueScreen(routeQuery: {'period': 'year'}),
    );
    await settleMocks(tester, rounds: 4);
  }

  List<String> texts(WidgetTester tester) => [
    for (final t in tester.widgetList<Text>(find.byType(Text)))
      t.data ?? t.textSpan?.toPlainText() ?? '',
  ];

  void expectNoPaymentWords(WidgetTester tester, String where) {
    for (final text in texts(tester)) {
      for (final word in ['encaissé', 'encaissement', 'paiements reçus']) {
        expect(text, isNot(contains(word)), reason: '$where: « $text »');
      }
      expect(
        text.toLowerCase(),
        isNot(contains('chiffre d’affaires')),
        reason: '$where: « $text »',
      );
      if (text.contains('encaiss')) {
        expect(
          text,
          contains('MyWeli n’encaisse rien'),
          reason: '$where: the only « encaiss » is the negation',
        );
      }
    }
  }

  testWidgets('with figures: « Réalisé » first, what it counts, and no '
      'payment anywhere — on every tab', (tester) async {
    await pump(tester);
    final all = texts(tester);
    expect(all, contains('Réalisé'));
    expect(all, contains('Rendez-vous terminés'));
    expect(all, isNot(contains('Total réalisé')), reason: 'the old card');
    expect(
      all,
      contains(
        'Montants calculés au prix affiché lors de la réservation. Les '
        'paiements se font entre vous et vos clients : MyWeli n’encaisse rien.',
      ),
    );
    expectNoPaymentWords(tester, 'Collaborateurs');
    for (final tab in ['Prestations', 'Canaux']) {
      await tester.tap(find.text(tab));
      await tester.pump();
      expectNoPaymentWords(tester, tab);
    }
  });

  testWidgets('a salon with no completed booking: the empty state promises '
      'completed bookings, not payments', (tester) async {
    // Every salon but the mock's first has no history (MockRevenueWorld).
    expect(MockRevenueWorld.salonWithHistory, isNot('provider2'));
    await pump(tester, service: _AnotherSalon());
    expect(find.text('Pas encore de revenus'), findsOneWidget);
    expect(
      find.text(
        'Vos revenus s’afficheront ici dès votre premier rendez-vous marqué '
        '« Terminé ».',
      ),
      findsOneWidget,
    );
    expectNoPaymentWords(tester, 'empty');
  });
}

/// The owner's « Revenus », answered from a salon of the mock world that has
/// no history.
class _AnotherSalon extends MockProService {
  @override
  Future<ApiResponse<RevenueAnalytics>> getRevenueAnalytics(
    SalonId providerId,
    RevenueQuery query,
  ) async => ApiResponse.success(
    MockRevenueWorld.analytics(
      const SalonId('provider2'),
      query,
      AppClock.now(),
    ).data!,
  );
}

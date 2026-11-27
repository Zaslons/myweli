import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/revenue_analytics.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_revenue_provider.dart';
import 'package:myweli/screens/provider/earnings/revenue_detail_screen.dart';
import 'package:myweli/screens/provider/earnings/revenue_ledger_screen.dart';
import 'package:myweli/screens/provider/earnings/revenue_screen.dart';
import 'package:myweli/widgets/pro/revenue/bar_series.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/revenue_fixtures.dart';
import '../support/revenue_service.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';
import '../support/surface.dart';

/// « Revenus » mounted in a router with its routes, for the taps that open
/// a detail, the ledger or a booking.
Future<GoRouter> pumpRevenue(
  WidgetTester tester, {
  required ProAuthProvider auth,
  required FakeRevenueService service,
  String location = '/pro/earnings',
  ThemeData? theme,
  bool pinPhone = true,
}) async {
  // A phone, tall enough that most of the screen is built: the default test
  // surface is 800 × 600.
  if (pinPhone) pinSurface(tester, size: const Size(390, 1600));
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/pro/earnings',
        builder: (_, s) => RevenueScreen(routeQuery: s.uri.queryParameters),
      ),
      GoRoute(
        path: '/pro/earnings/collaborateur/:id',
        builder: (_, s) => RevenueDetailScreen(
          axis: RevenueAxis.artist,
          rowKey: s.pathParameters['id']!,
          routeQuery: s.uri.queryParameters,
        ),
      ),
      GoRoute(
        path: '/pro/earnings/prestation/:id',
        builder: (_, s) => RevenueDetailScreen(
          axis: RevenueAxis.service,
          rowKey: s.pathParameters['id']!,
          routeQuery: s.uri.queryParameters,
        ),
      ),
      GoRoute(
        path: '/pro/earnings/canal/:id',
        builder: (_, s) => RevenueDetailScreen(
          axis: RevenueAxis.channel,
          rowKey: s.pathParameters['id']!,
          routeQuery: s.uri.queryParameters,
        ),
      ),
      GoRoute(
        path: '/pro/earnings/rendez-vous',
        builder: (_, s) =>
            RevenueLedgerScreen(routeQuery: s.uri.queryParameters),
      ),
      GoRoute(
        path: '/pro/appointment/:id',
        builder: (_, s) =>
            Scaffold(body: Text('booking ${s.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/pro/journal',
        builder: (_, _) => const Scaffold(body: Text('journal')),
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
    routerConfig: router,
    theme: theme,
  );
  await settleMocks(tester, rounds: 2);
  return router;
}

void main() {
  setUpAll(() async {
    AppClock.freeze(kRevenueNow);
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    setupDependencyInjection();
  });
  tearDownAll(AppClock.restore);
  setUp(() => freezeClock(kRevenueNow));

  Future<void> scrollTo(WidgetTester tester, Finder f) => tester
      .scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);

  testWidgets('success: the period, its comparison, the banner, the figures '
      'and their deltas', (tester) async {
    final auth = await signInPro(tester);
    final service = FakeRevenueService();
    await pumpRevenue(tester, auth: auth, service: service);

    expect(tester.takeException(), isNull);
    expect(service.asked.single.period, RevenuePeriod.month);
    expect(service.asked.single.date, isNull, reason: 'the server’s today');

    expect(find.text('Novembre 2026'), findsOneWidget);
    expect(find.text('(en cours)'), findsOneWidget);
    expect(
      find.textContaining('1er – 25 oct. 2026, même avancement'),
      findsOneWidget,
    );
    expect(find.text('4 rendez-vous passés à clôturer'), findsOneWidget);
    expect(find.text('Voir'), findsOneWidget);
    expect(find.text('Réalisé'), findsOneWidget);
    expect(find.text('+12 %'), findsNothing, reason: 'in a rich text');
    expect(find.textContaining('+12 %'), findsOneWidget);
    expect(find.text('Taux d’absence'), findsOneWidget);
    expect(find.text('5,9 %'), findsOneWidget);
    expect(find.text('Prévu'), findsOneWidget);
    expect(
      find.textContaining('encaiss'),
      findsNothing,
      reason: 'the price footnote, with « n’encaisse rien », is lower',
    );
  });

  Map<String, dynamic> zeroFigures() => revenueFigures(
    completedAmount: 0,
    completedCount: 0,
    averageTicket: null,
    noShowAmount: 0,
    noShowCount: 0,
    noShowRate: null,
    toCloseAmount: 0,
    toCloseCount: 0,
  );

  testWidgets('the labels of §3.3 on each tab, « estimé » and its footnote', (
    tester,
  ) async {
    final auth = await signInPro(tester);
    await pumpRevenue(tester, auth: auth, service: FakeRevenueService());

    await scrollTo(tester, find.text('Ancien collaborateur'));
    expect(find.text('Awa Koné'), findsOneWidget);
    expect(find.text('Konan Serge · a quitté l’équipe'), findsOneWidget);
    expect(find.text('Sans collaborateur attribué'), findsOneWidget);
    expect(find.text('Ancien collaborateur'), findsOneWidget);
    expect(
      find.textContaining('· estimé'),
      findsNothing,
      reason: 'no row of « Collaborateurs » rests on an estimate',
    );

    await tester.ensureVisible(find.text('Prestations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prestations'));
    await tester.pump();
    await tester.ensureVisible(find.textContaining('Tresses africaines'));
    await tester.pumpAndSettle();
    expect(find.text('750 000 FCFA · estimé'), findsOneWidget);
    expect(find.text('Nattes · prestation supprimée'), findsOneWidget);
    expect(find.text('Prestation supprimée'), findsOneWidget);
    await scrollTo(tester, find.textContaining('Estimé : réservation faite'));
    expect(
      find.text('Un rendez-vous à plusieurs prestations compte pour chacune.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Canaux'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Canaux'));
    await tester.pump();
    for (final label in [
      'Application MyWeli',
      'Site MyWeli',
      'Ajouté par le salon',
      'En ligne (avant le suivi)',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // The negation is the only « encaiss » on the screen.
    final encaiss = find.textContaining('encaiss');
    expect(encaiss, findsOneWidget);
    expect(
      tester.widget<Text>(encaiss).data,
      contains('MyWeli n’encaisse rien'),
    );
  });

  testWidgets('a row opens its detail on the same period; the detail hides '
      'its own axis and does not drill further', (tester) async {
    final auth = await signInPro(tester);
    final service = FakeRevenueService();
    final router = await pumpRevenue(
      tester,
      auth: auth,
      service: service,
      location: '/pro/earnings?period=week&date=2026-11-25&compare=year',
    );
    expect(service.asked.last.period, RevenuePeriod.week);
    expect(service.asked.last.compare, RevenueCompare.year);

    await scrollTo(tester, find.text('Awa Koné'));
    await tester.tap(find.text('Awa Koné'));
    await settleMocks(tester, rounds: 2);
    final uri = router.state.uri;
    expect(uri.path, '/pro/earnings/collaborateur/artist1');
    expect(uri.queryParameters['period'], 'week');
    expect(uri.queryParameters['date'], '2026-11-25');
    expect(service.asked.last.artistId, 'artist1');
    expect(service.asked.last.period, RevenuePeriod.week);

    expect(find.text('Awa Koné'), findsOneWidget, reason: 'the title');
    expect(find.text('Collaborateurs'), findsNothing);
    await scrollTo(tester, find.text('Nattes · prestation supprimée'));
    await tester.tap(find.text('Nattes · prestation supprimée'));
    await settleMocks(tester);
    expect(
      router.state.uri.path,
      '/pro/earnings/collaborateur/artist1',
      reason: 'one level on a phone',
    );
  });

  testWidgets('« Sans collaborateur attribué » opens as `none`', (
    tester,
  ) async {
    final auth = await signInPro(tester);
    final service = FakeRevenueService();
    final router = await pumpRevenue(tester, auth: auth, service: service);
    await scrollTo(tester, find.text('Sans collaborateur attribué'));
    await tester.tap(find.text('Sans collaborateur attribué'));
    await settleMocks(tester, rounds: 2);
    expect(router.state.uri.path, '/pro/earnings/collaborateur/none');
    expect(service.asked.last.artistId, RevenueQuery.kNoArtist);
    expect(find.text('Sans collaborateur attribué'), findsOneWidget);
  });

  testWidgets('the banner’s « Voir »: the ledger on « À clôturer » at the '
      'figures’ instant; coming back reloads', (tester) async {
    final auth = await signInPro(tester);
    final service = FakeRevenueService();
    final router = await pumpRevenue(tester, auth: auth, service: service);
    final before = service.asked.length;
    await tester.tap(find.text('Voir'));
    await settleMocks(tester, rounds: 2);
    final uri = router.state.uri;
    expect(uri.path, '/pro/earnings/rendez-vous');
    expect(uri.queryParameters['statut'], 'toClose');
    expect(uri.queryParameters['asOf'], '2026-11-25T14:30:00.000Z');
    expect(service.ledgerAsked.last.status, RevenueLedgerStatus.toClose);
    router.pop();
    await settleMocks(tester, rounds: 2);
    expect(service.asked.length, before + 1, reason: 'the figures reloaded');
  });

  testWidgets('the period bar: a chip keeps the anchor, ‹ › step from the '
      'answer', (tester) async {
    final auth = await signInPro(tester);
    final service = FakeRevenueService();
    await pumpRevenue(tester, auth: auth, service: service);

    await tester.tap(find.byTooltip('Période précédente'));
    await settleMocks(tester);
    expect(service.asked.last.period, RevenuePeriod.month);
    expect(service.asked.last.date, revenueDay(2026, 10, 1));

    service.analytics = (q) => revenueAnalyticsJson(
      from: '2026-10-01',
      to: '2026-10-31',
      inProgress: false,
    );
    await tester.tap(find.byTooltip('Période précédente'));
    await settleMocks(tester);
    service.hold = Completer<void>();
    await tester.tap(find.text('Semaine'));
    await tester.pump();
    expect(service.asked.last.period, RevenuePeriod.week);
    expect(
      service.asked.last.date,
      revenueDay(2026, 10, 1),
      reason: 'a past month → its first week',
    );
    expect(
      find.text('28 sept. – 4 oct. 2026'),
      findsOneWidget,
      reason: 'the bar updates at once, before the answer',
    );
    expect(
      find.text('Réalisé'),
      findsNothing,
      reason: 'never the previous period’s figures under the new title',
    );
    service.hold!.complete();
    await settleMocks(tester);
  });

  testWidgets(
    '« Comparé à »: the sheet, and the choice holds for the session',
    (tester) async {
      final auth = await signInPro(tester);
      final service = FakeRevenueService();
      await pumpRevenue(tester, auth: auth, service: service);
      await tester.tap(find.textContaining('Comparé à'));
      await tester.pumpAndSettle();
      expect(find.text('Comparer à'), findsOneWidget);
      expect(find.text('Même période l’an dernier'), findsOneWidget);
      service.analytics = (q) => revenueAnalyticsJson(
        compareMode: 'none',
        groups: [revenueGroup(withPrevious: false)],
      );
      await tester.tap(find.text('Aucune comparaison'));
      await settleMocks(tester, rounds: 2);
      expect(service.asked.last.compare, RevenueCompare.none);
      expect(find.textContaining('Aucune comparaison'), findsOneWidget);
      expect(
        find.textContaining('+12 %'),
        findsNothing,
        reason: 'no comparison, no delta',
      );
    },
  );

  testWidgets('« Dates… »: MyWeli’s picker, the error under « Au », never a '
      'Material picker', (tester) async {
    final semantics = tester.ensureSemantics();
    final auth = await signInPro(tester);
    final service = FakeRevenueService();
    await pumpRevenue(tester, auth: auth, service: service);
    await tester.tap(find.text('Dates…'));
    await tester.pumpAndSettle();
    expect(find.text('Du'), findsOneWidget);
    expect(find.text('Au'), findsOneWidget);

    Future<void> pick(String field, String day) async {
      await tester.tap(find.bySemanticsLabel(RegExp('^$field :')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      await tester.tap(find.bySemanticsLabel(RegExp(day)));
      await tester.pumpAndSettle();
    }

    await pick('Du', 'dimanche 15 novembre 2026');
    await pick('Au', 'mardi 10 novembre 2026');
    expect(
      find.text('La date de fin précède la date de début'),
      findsOneWidget,
    );
    final show = find.widgetWithText(ElevatedButton, 'Afficher');
    expect(tester.widget<ElevatedButton>(show).onPressed, isNull);

    await pick('Au', 'vendredi 20 novembre 2026');
    expect(find.text('La date de fin précède la date de début'), findsNothing);
    await tester.tap(show);
    await settleMocks(tester, rounds: 2);
    expect(service.asked.last.period, RevenuePeriod.custom);
    expect(service.asked.last.from, revenueDay(2026, 11, 15));
    expect(service.asked.last.to, revenueDay(2026, 11, 20));
    semantics.dispose();
  });

  testWidgets('a salon with no completed booking ever: « Pas encore de '
      'revenus », and « Prévu » when bookings are coming', (tester) async {
    final auth = await signInPro(tester);
    final service = FakeRevenueService()
      ..analytics = (_) => revenueAnalyticsJson(
        everCompleted: false,
        groups: [
          revenueGroup(
            current: zeroFigures(),
            withPrevious: false,
            byArtist: [],
            byService: [],
            byChannel: [],
          ),
        ],
      );
    final router = await pumpRevenue(tester, auth: auth, service: service);
    expect(find.text('Pas encore de revenus'), findsOneWidget);
    expect(find.text('Prévu'), findsOneWidget);
    expect(find.text('Réalisé'), findsNothing);
    await tester.tap(find.text('Voir les rendez-vous'));
    await settleMocks(tester);
    expect(router.state.uri.path, '/pro/journal');
  });

  testWidgets('a period with nothing completed: the figures at 0, no chart, '
      'and « Période précédente »', (tester) async {
    final auth = await signInPro(tester);
    final service = FakeRevenueService()
      ..analytics = (_) => revenueAnalyticsJson(
        groups: [
          revenueGroup(
            current: zeroFigures(),
            byArtist: [],
            byService: [],
            byChannel: [],
          ),
        ],
      );
    await pumpRevenue(tester, auth: auth, service: service);
    expect(find.text('0 FCFA'), findsOneWidget);
    expect(find.text('Évolution'), findsNothing);
    await scrollTo(
      tester,
      find.text('Aucun rendez-vous terminé sur cette période'),
    );
    await tester.ensureVisible(find.text('Période précédente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Période précédente'));
    await settleMocks(tester);
    expect(service.asked.last.date, revenueDay(2026, 10, 1));
  });

  testWidgets('a future period: « Rien de terminé pour l’instant »', (
    tester,
  ) async {
    final auth = await signInPro(tester);
    final service = FakeRevenueService()
      ..analytics = (_) => revenueAnalyticsJson(
        from: '2026-12-01',
        to: '2026-12-31',
        inProgress: false,
        groups: [
          revenueGroup(
            current: zeroFigures(),
            byArtist: [],
            byService: [],
            byChannel: [],
          ),
        ],
      );
    await pumpRevenue(
      tester,
      auth: auth,
      service: service,
      location: '/pro/earnings?period=month&date=2026-12-01',
    );
    expect(find.text('Prévu'), findsOneWidget);
    await scrollTo(tester, find.text('Rien de terminé pour l’instant'));
    expect(find.text('Cette période n’a pas commencé.'), findsOneWidget);
  });

  testWidgets('403: « Réservé au propriétaire », no « Réessayer »', (
    tester,
  ) async {
    final auth = await signInPro(tester);
    final service = FakeRevenueService()
      ..failure = ApiResponse.error(
        'Action non autorisée pour ce salon.',
        code: 'forbidden',
      );
    await pumpRevenue(tester, auth: auth, service: service);
    expect(find.text('Réservé au propriétaire'), findsOneWidget);
    expect(
      find.text('Seul le propriétaire du salon voit les revenus.'),
      findsOneWidget,
    );
    expect(find.text('Réessayer'), findsNothing);
    expect(find.text('Chargement impossible'), findsNothing);
  });

  testWidgets('a failure: « Chargement impossible », « Réessayer » asks the '
      'same period', (tester) async {
    final auth = await signInPro(tester);
    final service = FakeRevenueService()
      ..failure = ApiResponse.error(
        'Pas de connexion. Réessayez.',
        code: 'network',
      );
    await pumpRevenue(
      tester,
      auth: auth,
      service: service,
      location: '/pro/earnings?period=year&date=2025-03-01',
    );
    expect(find.text('Chargement impossible'), findsOneWidget);
    service.failure = null;
    await tester.tap(find.text('Réessayer'));
    await settleMocks(tester);
    expect(service.asked, hasLength(2));
    expect(service.asked.last, service.asked.first);
    expect(find.text('Réalisé'), findsOneWidget);
  });

  testWidgets('two currencies: one segment each, never a sum', (tester) async {
    final auth = await signInPro(tester);
    final service = FakeRevenueService()
      ..analytics = (_) => revenueAnalyticsJson(
        groups: [
          revenueGroup(),
          revenueGroup(
            currency: 'XAF',
            current: revenueFigures(completedAmount: 70000, completedCount: 2),
          ),
        ],
      );
    await pumpRevenue(tester, auth: auth, service: service);
    expect(find.text('XOF · franc CFA (UEMOA)'), findsOneWidget);
    expect(find.text('XAF · franc CFA (CEMAC)'), findsOneWidget);
    expect(find.text('1 250 000 FCFA'), findsOneWidget);
    expect(
      find.text('1 320 000 FCFA'),
      findsNothing,
      reason: 'the two groups added',
    );
    await tester.tap(find.text('XAF · franc CFA (CEMAC)'));
    await tester.pump();
    expect(find.text('70 000 FCFA'), findsOneWidget);
    expect(find.text('1 250 000 FCFA'), findsNothing);
  });

  testWidgets('one sentence per figure for a screen reader (§12.3)', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final auth = await signInPro(tester);
    await pumpRevenue(tester, auth: auth, service: FakeRevenueService());
    expect(
      find.bySemanticsLabel(
        'Réalisé : 1 250 000 FCFA, en hausse de 12 % par '
        'rapport à la période 1er – 25 oct. 2026, même avancement',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        // « d’absence »: `.` for the apostrophe (design_system_pin_test).
        RegExp(r'^Taux d.absence : 5,9.%, en baisse de 1,2 point'),
      ),
      findsOneWidget,
    );
    await scrollTo(tester, find.text('Awa Koné'));
    expect(
      find.bySemanticsLabel(
        'Awa Koné, 420 000 FCFA, 34 % du réalisé, 16 rendez-vous, '
        'panier moyen 26 250 FCFA, en hausse de 9 % par rapport à la '
        'période 1er – 25 oct. 2026, même avancement. Ouvrir le détail.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('the chart: one node; increase and decrease move the '
      'selection, told apart by fill', (tester) async {
    final semantics = tester.ensureSemantics();
    final auth = await signInPro(tester);
    await pumpRevenue(tester, auth: auth, service: FakeRevenueService());
    final chart = find.bySemanticsLabel('Évolution du réalisé');
    await scrollTo(tester, chart);
    expect(chart, findsOneWidget);
    final node = tester.getSemantics(chart);
    expect(node.value, startsWith('Réalisé sur la période'));
    node.owner!.performAction(node.id, SemanticsAction.increase);
    await tester.pump();
    expect(
      tester.getSemantics(chart).value,
      'dim. 1er nov. · 21 000 FCFA · 2 rendez-vous',
    );
    final fills = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(BarSeries),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((b) => (b.decoration as BoxDecoration).color)
        .toSet();
    expect(
      fills,
      containsAll([const Color(0xFF000000), const Color(0xFF8A8A8A)]),
    );
    semantics.dispose();
  });

  testWidgets('the ledger: filters, « Afficher plus », each row opens its '
      'booking', (tester) async {
    final auth = await signInPro(tester);
    final service = FakeRevenueService()
      ..ledger = (status, page) => revenueLedgerJson(
        items: [
          for (var i = 0; i < 20; i++)
            revenueLedgerRow(
              id: 'p${page}_$i',
              amount: 5000,
              totalPrice: 12000,
            ),
        ],
        page: page,
        total: 25,
      );
    final router = await pumpRevenue(
      tester,
      auth: auth,
      service: service,
      location:
          '/pro/earnings/rendez-vous?period=month&serviceId=svc1&statut=completed',
    );
    expect(service.ledgerAsked.single.query.serviceId, 'svc1');
    expect(find.text('sur 12 000 FCFA'), findsWidgets);
    await scrollTo(tester, find.text('Afficher plus'));
    expect(find.text('20 sur 25 rendez-vous'), findsOneWidget);
    await tester.ensureVisible(find.text('Afficher plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Afficher plus'));
    await settleMocks(tester);
    expect(service.ledgerAsked.last.page, 2);

    await tester.tap(find.text('Absents'));
    await settleMocks(tester);
    expect(service.ledgerAsked.last.status, RevenueLedgerStatus.noShow);
    expect(service.ledgerAsked.last.page, 1);

    await tester.fling(
      find.byType(Scrollable).last,
      const Offset(0, 3000),
      3000,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 000 FCFA').first);
    await settleMocks(tester);
    final uri = router.state.uri;
    expect(uri.path, '/pro/appointment/p1_0');
    expect(uri.queryParameters['salon'], 'provider1');
  });

  testWidgets('an empty ledger says which filter is empty', (tester) async {
    final auth = await signInPro(tester);
    final service = FakeRevenueService()
      ..ledger = (_, _) => revenueLedgerJson(items: [], total: 0);
    await pumpRevenue(
      tester,
      auth: auth,
      service: service,
      location: '/pro/earnings/rendez-vous?period=month&statut=upcoming',
    );
    expect(find.text('Aucun rendez-vous'), findsOneWidget);
    expect(
      find.text('Aucun rendez-vous à venir sur cette période.'),
      findsOneWidget,
    );
  });
}

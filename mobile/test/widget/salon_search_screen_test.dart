import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/router/app_router.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/models/provider_page.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/home/home_screen.dart';
import 'package:myweli/services/interfaces/provider_service_interface.dart';
import 'package:myweli/services/mock/mock_appointment_service.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_favorites_service.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:myweli/widgets/common/app_button.dart';
import 'package:myweli/widgets/common/app_chip.dart';
import 'package:myweli/widgets/common/app_skeleton.dart';
import 'package:myweli/widgets/provider/provider_card.dart';
import 'package:provider/provider.dart' hide Provider;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/surface.dart';

/// docs/design/consumer-search.md §8, « A4 (app) — Widget »: the salon
/// list's search as a person meets it, and the home it no longer leaks into.

/// The salons each search finds — [MockProviderService]'s own matching and
/// paging over [salons] — or a held answer, or a failure.
class _Search extends MockProviderService {
  List<Provider> salons = MockData.providers;
  final asked = <ProviderQuery>[];
  bool hold = false;
  final held = <Completer<ApiResponse<ProviderPage>>>[];

  /// Fail the searches whose page is [failPage] (null: none).
  int? failPage;

  void reset() {
    salons = MockData.providers;
    asked.clear();
    held.clear();
    hold = false;
    failPage = null;
  }

  @override
  Future<ApiResponse<ProviderPage>> searchProviders(ProviderQuery query) {
    asked.add(query);
    if (hold) {
      final c = Completer<ApiResponse<ProviderPage>>();
      held.add(c);
      return c.future;
    }
    if (failPage == query.page) {
      return Future.delayed(
        const Duration(milliseconds: 300),
        () => ApiResponse.error(kNoConnectionMessage, code: 'network'),
      );
    }
    return MockProviderService(salons: salons).searchProviders(query);
  }

  @override
  Future<ApiResponse<List<Provider>>> getFeaturedProviders() =>
      MockProviderService(salons: salons).getFeaturedProviders();
}

Provider _salon(String id, {String commune = 'Plateau'}) => MockData
    .providers
    .first
    .copyWith(id: SalonId(id), name: 'Salon $id', commune: commune);

/// The real `/providers` route's builder — its `?category=` and `?focus=`
/// reading is part of what is tested.
GoRoute _appRoute(String path) => AppRouter.router.configuration.routes
    .whereType<GoRoute>()
    .firstWhere((r) => r.path == path);

void main() {
  final service = _Search();

  // The services are `late final`: set once for the file, as
  // salon_location_map_test.dart does, the salon reads reset before each test.
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    serviceLocator.providerService = service;
    serviceLocator.authService = MockAuthService();
    serviceLocator.favoritesService = MockFavoritesService();
    serviceLocator.appointmentService = MockAppointmentService();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service.reset();
  });

  late ProviderProvider providers;

  /// Signed out, its session read finished — built outside the fake clock,
  /// as salon_location_map_test.dart does: created lazily under it, its read
  /// left a timer pending at the end of every test.
  Future<AuthProvider> signedOut(WidgetTester tester) async {
    late AuthProvider auth;
    await tester.runAsync(() async {
      auth = AuthProvider();
      for (var i = 0; i < 60 && auth.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });
    return auth;
  }

  /// [run] — a read that waits on the mocks' latency — let through the fake
  /// clock: awaited directly, it never ends.
  Future<void> let(WidgetTester tester, Future<void> Function() run) async {
    unawaited(run());
    await settleMocks(tester, rounds: 2);
  }

  Future<GoRouter> pumpList(
    WidgetTester tester, {
    String location = '/providers',
    Size size = const Size(420, 2400),
    bool settle = true,
  }) async {
    pinSurface(tester, size: size);
    providers = ProviderProvider();
    final auth = await signedOut(tester);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(path: '/providers', builder: _appRoute('/providers').builder),
        GoRoute(
          path: '/provider/:id',
          builder: (_, s) =>
              Scaffold(body: Text('Page de ${s.pathParameters['id']}')),
        ),
      ],
    );
    await tester.pumpWidget(
      wrapApp(
        routerConfig: router,
        providers: [
          ChangeNotifierProvider.value(value: providers),
          ChangeNotifierProvider(create: (_) => FavoritesProvider()),
          ChangeNotifierProvider.value(value: auth),
        ],
      ),
    );
    if (settle) await settleMocks(tester);
    return router;
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 350));
    await settleMocks(tester);
  }

  Iterable<String> cards(WidgetTester tester) => tester
      .widgetList<ProviderCard>(find.byType(ProviderCard))
      .map((c) => c.provider.id);

  bool chipLit(WidgetTester tester, String label) =>
      tester
          .widget<AppChip>(
            find.ancestor(of: find.text(label), matching: find.byType(AppChip)),
          )
          .selected ==
      true;

  group('the field (§2.2)', () {
    testWidgets('« Rechercher un salon » to a screen reader, the hint as an '
        'example', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester);
      expect(find.text('Salon, prestation ou commune'), findsOneWidget);
      // ONE node, the text field's: named first, the example after it.
      final empty = tester.getSemantics(find.byType(TextField));
      expect(empty.label, startsWith('Rechercher un salon'));
      expect(empty.label, contains('Salon, prestation ou commune'));
      expect(empty.getSemanticsData().flagsCollection.isTextField, isTrue);

      // Typed into, it keeps its name: the hint is gone, the name is not.
      await type(tester, 'tresses');
      final typed = tester.getSemantics(find.byType(TextField));
      expect(typed.label, 'Rechercher un salon');
      expect(typed.value, 'tresses');
      handle.dispose();
    });

    testWidgets('from the home bar: the cursor in it, keyboard up', (
      tester,
    ) async {
      await pumpList(tester, location: '/providers?focus=search');
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
    });

    testWidgets('from a chip: the keyboard down, that chip lit', (
      tester,
    ) async {
      await pumpList(tester, location: '/providers?category=nails');
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isFalse);
      expect(chipLit(tester, 'Onglerie'), isTrue);
      expect(chipLit(tester, 'Tous'), isFalse);
      expect(service.asked.first.category, 'nails');
    });

    testWidgets('an unknown ?category= opens on « Tous » — the website\'s '
        'old « nail »', (tester) async {
      await pumpList(tester, location: '/providers?category=nail');
      expect(chipLit(tester, 'Tous'), isTrue);
      expect(service.asked.first.category, isNull);
    });

    testWidgets('one letter: the helper line, and the results stay', (
      tester,
    ) async {
      await pumpList(tester);
      final before = cards(tester).toList();
      await type(tester, 't');
      expect(find.text('Tapez au moins 2 lettres'), findsOneWidget);
      expect(cards(tester), before);
      expect(service.asked, hasLength(1));
      await type(tester, 'tr');
      expect(find.text('Tapez au moins 2 lettres'), findsNothing);
    });

    testWidgets('the text finds what the server finds, and ✕ clears it', (
      tester,
    ) async {
      await pumpList(tester);
      expect(find.byTooltip('Effacer la recherche'), findsNothing);
      await type(tester, 'beaute');
      expect(cards(tester), ['provider2'], reason: '« Beauté Divine »');
      expect(find.text('1 salon'), findsOneWidget);

      await tester.tap(find.byTooltip('Effacer la recherche'));
      await settleMocks(tester);
      expect(find.text('beaute'), findsNothing);
      expect(service.asked.last.text, '');
      expect(cards(tester), hasLength(MockData.providers.length));
    });

    testWidgets('a service finds its salon: « manucure »', (tester) async {
      await pumpList(tester);
      await type(tester, 'MANUCURE');
      expect(cards(tester), ['provider3']);
    });

    testWidgets('the keyboard\'s « Rechercher » lowers the keyboard', (
      tester,
    ) async {
      await pumpList(tester, location: '/providers?focus=search');
      await tester.enterText(find.byType(TextField), 'spa');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(service.asked.last.text, 'spa', reason: 'at once, no wait');
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isFalse);
      await settleMocks(tester);
    });

    testWidgets('100 characters at most', (tester) async {
      await pumpList(tester);
      await type(tester, 'a' * 140);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.controller.text.length, 100);
      expect(find.textContaining('/100'), findsNothing, reason: 'no counter');
    });
  });

  group('the count (§2.5)', () {
    testWidgets('the server\'s total, not the salons on screen', (
      tester,
    ) async {
      service.salons = [for (var i = 0; i < 42; i++) _salon('s$i')];
      await pumpList(tester);
      expect(find.text('42 salons'), findsOneWidget);
      expect(cards(tester).length, lessThanOrEqualTo(20));
    });

    testWidgets('« à Cocody » with a commune', (tester) async {
      await pumpList(tester, settle: false);
      await let(tester, () => providers.setCommune('Cocody'));
      expect(find.text('1 salon à Cocody'), findsOneWidget);
    });

    testWidgets('« Recherche… » while a new search is out, the results kept; '
        'nothing while the first page loads', (tester) async {
      service.hold = true;
      await pumpList(tester, settle: false);
      await tester.pump();
      expect(find.textContaining('salon'), findsNothing);
      expect(find.text('Recherche…'), findsNothing);
      service.held.first.complete(
        ApiResponse.success(
          ProviderPage(
            items: MockData.providers,
            page: 1,
            pageSize: 20,
            total: 4,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(); // the answer crosses two awaits
      expect(find.text('4 salons'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'spa');
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Recherche…'), findsOneWidget);
      expect(cards(tester), hasLength(4), reason: 'no skeleton per key');
      service.held.last.complete(
        ApiResponse.success(
          const ProviderPage(items: [], page: 1, pageSize: 20, total: 0),
        ),
      );
      await tester.pump();
    });

    testWidgets('a search over an empty answer: its sentence stays, '
        '« Recherche… » above it, no skeleton', (tester) async {
      await pumpList(tester);
      await type(tester, 'zzz');
      expect(find.text('Aucun résultat pour « zzz »'), findsOneWidget);
      service.hold = true;
      await tester.enterText(find.byType(TextField), 'zzzy');
      await tester.pump(const Duration(milliseconds: 350));
      expect(service.held, hasLength(1), reason: 'C: the search is out');
      expect(find.text('Aucun résultat pour « zzz »'), findsOneWidget);
      expect(find.text('Recherche…'), findsOneWidget);
      expect(find.byType(SkeletonCardList), findsNothing);
      service.held.single.complete(
        ApiResponse.success(
          const ProviderPage(items: [], page: 1, pageSize: 20, total: 0),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Aucun résultat pour « zzzy »'), findsOneWidget);
    });

    testWidgets('« Réessayer » after a failure: the skeleton, not the error '
        'left standing', (tester) async {
      service.failPage = 1;
      await pumpList(tester);
      expect(find.text('Chargement impossible'), findsOneWidget);
      service
        ..failPage = null
        ..hold = true;
      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      expect(find.byType(SkeletonCardList), findsOneWidget);
      expect(find.text('Chargement impossible'), findsNothing);
      service.held.single.complete(
        ApiResponse.success(
          ProviderPage(
            items: MockData.providers,
            page: 1,
            pageSize: 20,
            total: MockData.providers.length,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(cards(tester), hasLength(MockData.providers.length));
    });

    testWidgets('a pull that failed keeps the salons — and says it failed', (
      tester,
    ) async {
      await pumpList(tester);
      tester.takeAnnouncements();
      service.failPage = 1;
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 400),
        1000,
      );
      await settleMocks(tester, rounds: 2);
      expect(service.asked, hasLength(2), reason: 'C: the pull searched');
      expect(cards(tester), hasLength(MockData.providers.length));
      final said = [for (final a in tester.takeAnnouncements()) a.message];
      expect(said, ['Chargement impossible. $kNoConnectionMessage']);
      expect(said, isNot(contains('Liste mise à jour')));
    });

    testWidgets('an answer under another screen is not read over it', (
      tester,
    ) async {
      final router = await pumpList(tester);
      unawaited(router.push('/provider/provider2'));
      await settleMocks(tester);
      tester.takeAnnouncements();
      // The commune changes while the list is under the salon page.
      await let(tester, () => providers.setCommune('Cocody'));
      expect(service.asked.last.commune, 'Cocody', reason: 'C: it searched');
      expect(tester.takeAnnouncements(), isEmpty);
      router.pop();
      await settleMocks(tester);
      expect(find.text('1 salon à Cocody'), findsOneWidget);
      expect(tester.takeAnnouncements(), isEmpty, reason: 'not a new answer');
    });

    testWidgets('each answer is announced once — the count, then the empty '
        'sentence', (tester) async {
      await pumpList(tester);
      await type(tester, 'divine');
      await type(tester, 'zzz');
      final said = [for (final a in tester.takeAnnouncements()) a.message];
      expect(said, ['4 salons', '1 salon', 'Aucun résultat pour « zzz »']);
    });
  });

  group('the chips (§2.4)', () {
    testWidgets('« Tous » and the five, on the list', (tester) async {
      await pumpList(tester);
      for (final label in [
        'Tous',
        'Coiffure',
        'Barbier',
        'Onglerie',
        'Spa',
        'Massage',
      ]) {
        expect(find.widgetWithText(AppChip, label), findsOneWidget);
      }
    });

    testWidgets('a chip narrows the same search; the text stays; the lit '
        'chip again removes it', (tester) async {
      await pumpList(tester);
      await type(tester, 'salon');
      await tester.tap(find.text('Barbier'));
      await settleMocks(tester);
      expect(service.asked.last.text, 'salon');
      expect(service.asked.last.category, 'barber');
      expect(chipLit(tester, 'Barbier'), isTrue);
      // Both barbers say « salon » somewhere; the other two salons are not
      // barbers.
      expect(cards(tester), ['provider1', 'provider4']);

      await tester.tap(find.text('Barbier'));
      await settleMocks(tester);
      expect(service.asked.last.category, isNull);
      expect(chipLit(tester, 'Tous'), isTrue);
    });
  });

  group('« Afficher plus de salons » (§2.6)', () {
    for (final grid in [false, true]) {
      testWidgets('appends the next 20, in the ${grid ? 'grid' : 'list'}', (
        tester,
      ) async {
        service.salons = [
          for (var i = 0; i < 25; i++) _salon('s${'$i'.padLeft(2, '0')}'),
        ];
        await pumpList(tester, size: const Size(420, 20000));
        if (grid) {
          await tester.tap(find.byTooltip('Afficher en grille'));
          await tester.pump();
        }
        expect(cards(tester), hasLength(20));
        final more = find.text('Afficher plus de salons');
        expect(more, findsOneWidget);

        await tester.tap(more);
        await tester.pump();
        // A loader in its place: the same button, loading — not a button
        // gone, which a footer that vanished would also pass.
        expect(
          tester
              .widget<AppButton>(
                find.byWidgetPredicate(
                  (w) => w is AppButton && w.text == 'Afficher plus de salons',
                ),
              )
              .isLoading,
          isTrue,
        );
        await settleMocks(tester);
        expect(cards(tester), hasLength(25));
        expect(more, findsNothing, reason: 'nothing more');
        expect(service.asked.last.page, 2);
      });
    }

    testWidgets('a failed page: the salons stay, the failure and « Réessayer » '
        'in the button\'s place', (tester) async {
      service.salons = [for (var i = 0; i < 25; i++) _salon('f$i')];
      await pumpList(tester, size: const Size(420, 20000));
      service.failPage = 2;
      await tester.tap(find.text('Afficher plus de salons'));
      await settleMocks(tester);
      expect(cards(tester), hasLength(20));
      expect(find.text('Impossible d’afficher la suite.'), findsOneWidget);

      service.failPage = null;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Réessayer'));
      await settleMocks(tester);
      expect(cards(tester), hasLength(25));
    });
  });

  group('the states (§2.9)', () {
    testWidgets('the first page failed: « Chargement impossible » and '
        '« Réessayer »', (tester) async {
      service.failPage = 1;
      await pumpList(tester);
      expect(find.text('Chargement impossible'), findsOneWidget);
      expect(find.text(kNoConnectionMessage), findsOneWidget);
      service.failPage = null;
      await tester.tap(find.text('Réessayer'));
      await settleMocks(tester);
      expect(cards(tester), hasLength(MockData.providers.length));
    });
  });

  group('empty: one sentence, one way out (§2.10)', () {
    Future<void> emptyWith(
      WidgetTester tester, {
      String? text,
      bool today = false,
      String? category,
      String? commune,
    }) async {
      service.salons = [_salon('elsewhere', commune: 'Bingerville')];
      await pumpList(
        tester,
        location: category == null
            ? '/providers'
            : '/providers?category=$category',
        settle: false,
      );
      // Something is public: the featured read answered with a salon.
      await let(tester, providers.loadFeaturedProviders);
      if (commune != null) {
        await let(tester, () => providers.setCommune(commune));
      }
      if (today) {
        await tester.tap(find.text('Disponible aujourd’hui'));
        await settleMocks(tester);
      }
      if (text != null) await type(tester, text);
    }

    testWidgets('a text: « Aucun résultat pour … », « Effacer la recherche »', (
      tester,
    ) async {
      await emptyWith(tester, text: 'tresses', commune: 'Cocody');
      expect(find.text('Aucun résultat pour « tresses »'), findsOneWidget);
      expect(
        find.text(
          'Vérifiez l’orthographe, ou cherchez une prestation : '
          '« tresses », « manucure »…',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Effacer la recherche'));
      await settleMocks(tester);
      expect(service.asked.last.text, '');
      expect(find.text('tresses'), findsNothing, reason: 'the field emptied');
    });

    // §2.10's order: the text is the most specific narrowing, so it wins
    // over « Disponible aujourd’hui » and over a category.
    testWidgets('a text with « Disponible aujourd’hui »: the text\'s row', (
      tester,
    ) async {
      await emptyWith(tester, text: 'tresses', today: true);
      expect(find.text('Aucun résultat pour « tresses »'), findsOneWidget);
      expect(find.text('Aucun salon disponible aujourd’hui'), findsNothing);
    });

    testWidgets('a text with a category and a commune: the text\'s row', (
      tester,
    ) async {
      await emptyWith(
        tester,
        text: 'tresses',
        category: 'spa',
        commune: 'Cocody',
      );
      expect(find.text('Aucun résultat pour « tresses »'), findsOneWidget);
      expect(find.textContaining('cette catégorie'), findsNothing);
    });

    testWidgets('a category: « Aucun salon dans cette catégorie à Cocody »', (
      tester,
    ) async {
      await emptyWith(tester, category: 'spa', commune: 'Cocody');
      expect(
        find.text('Aucun salon dans cette catégorie à Cocody'),
        findsOneWidget,
      );
      await tester.tap(find.text('Toutes les catégories'));
      await settleMocks(tester);
      expect(service.asked.last.category, isNull);
    });

    testWidgets('a category, no commune: no « à »', (tester) async {
      await emptyWith(tester, category: 'massage');
      expect(find.text('Aucun salon dans cette catégorie'), findsOneWidget);
    });

    testWidgets('a commune: « Aucun salon à Cocody », « Voir toutes les '
        'communes »', (tester) async {
      await emptyWith(tester, commune: 'Cocody');
      expect(find.text('Aucun salon à Cocody'), findsOneWidget);
      await tester.tap(find.text('Voir toutes les communes'));
      await settleMocks(tester, rounds: 2);
      expect(providers.selectedCommune, isNull);
      expect(cards(tester), ['elsewhere']);
    });

    testWidgets('« Disponible aujourd’hui » comes before the category and '
        'the commune; « Retirer ce filtre » removes it', (tester) async {
      await emptyWith(tester, today: true, category: 'spa', commune: 'Cocody');
      expect(find.text('Aucun salon disponible aujourd’hui'), findsOneWidget);
      expect(
        find.text('Les autres jours ont peut-être de la place.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retirer ce filtre'));
      await settleMocks(tester);
      expect(service.asked.last.availableToday, isFalse);
      expect(service.asked.last.category, 'spa', reason: 'only that one');
      expect(
        find.text('Aucun salon dans cette catégorie à Cocody'),
        findsOneWidget,
      );
    });

    testWidgets('no salon public at all: the last row, whatever the filters', (
      tester,
    ) async {
      service.salons = const [];
      await pumpList(tester, settle: false);
      await let(tester, providers.loadFeaturedProviders);
      await type(tester, 'tresses');
      expect(find.text('Aucun salon pour l’instant'), findsOneWidget);
      expect(
        find.text('Aucun salon n’accepte encore de réservations sur MyWeli.'),
        findsOneWidget,
      );
      expect(find.text('Effacer la recherche'), findsNothing);
      expect(find.textContaining('orthographe'), findsNothing);
    });
  });

  group('copies the app keeps current (§3.2)', () {
    testWidgets('a review posted while the search is open moves its card: '
        '« (89) » → « (90) »', (tester) async {
      await pumpList(tester);
      await type(tester, 'divine');
      expect(cards(tester), ['provider2']);
      expect(find.text('(89)'), findsOneWidget, reason: 'C: Beauté Divine');
      providers.addReviewLocally(
        Review(
          id: 'r-new',
          providerId: SalonId('provider2'),
          userId: 'u1',
          userName: 'Awa',
          rating: 5,
          text: 'Très bien',
          createdAt: DateTime(2026, 11, 25),
        ),
      );
      await tester.pump();
      expect(find.text('(90)'), findsOneWidget);
      expect(find.text('(89)'), findsNothing);
    });
  });

  group('a salon, then back (§2.1 step 6)', () {
    testWidgets('the text, the chip and the pages are where they were', (
      tester,
    ) async {
      service.salons = [
        for (var i = 0; i < 25; i++) _salon('b${'$i'.padLeft(2, '0')}'),
      ];
      final router = await pumpList(tester, size: const Size(420, 20000));
      await type(tester, 'salon');
      await tester.tap(find.text('Afficher plus de salons'));
      await settleMocks(tester);
      final asked = service.asked.length;

      unawaited(router.push('/provider/b03'));
      await settleMocks(tester);
      // The salon page reads its salon: a notification, same commune.
      await let(tester, () => providers.loadProviderById(SalonId('b03')));
      router.pop();
      await settleMocks(tester);

      expect(find.text('salon'), findsOneWidget);
      expect(cards(tester), hasLength(25));
      expect(service.asked, hasLength(asked), reason: 'no search again');
    });
  });

  group('the home is no longer the list (§2.7, the defect)', () {
    Future<GoRouter> pumpHome(WidgetTester tester) async {
      pinSurface(tester, size: const Size(1400, 4000));
      providers = ProviderProvider();
      final auth = await signedOut(tester);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
          GoRoute(path: '/providers', builder: _appRoute('/providers').builder),
        ],
      );
      await tester.pumpWidget(
        wrapApp(
          routerConfig: router,
          providers: [
            ChangeNotifierProvider.value(value: providers),
            ChangeNotifierProvider(create: (_) => FavoritesProvider()),
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider(create: (_) => AppointmentProvider()),
          ],
        ),
      );
      await settleMocks(tester, rounds: 3);
      return router;
    }

    // « Barbier » and « Mieux notés » on the list leaking into the home:
    // home_nearby_leak_test.dart, written red against `main` first.

    // A booking with no salon name of its own (an older server) takes it
    // from the home's list (decision 199). « Disponible aujourd’hui » on the
    // list narrowed that list, and the card fell back to « Salon ». Watched
    // red against `main` `da5faa09` with the same steps.
    testWidgets('after « Disponible aujourd’hui » on the list, a booking '
        'still names « Salon Excellence »', (tester) async {
      // A Monday: Salon Excellence is closed, so the filter drops it.
      freezeClock(DateTime.utc(2026, 11, 23, 10));
      pinSurface(tester, size: const Size(420, 2400));
      providers = ProviderProvider();
      final auth = await signedOut(tester);
      final booking = MockData.appointments.firstWhere(
        (a) => a.providerId == SalonId('provider1'),
      );
      expect(booking.providerName, isNull, reason: 'C: it reads the list');
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: AppointmentCard(appointment: booking, onTap: () {}),
            ),
          ),
          GoRoute(path: '/providers', builder: _appRoute('/providers').builder),
        ],
      );
      await tester.pumpWidget(
        wrapApp(
          routerConfig: router,
          providers: [
            ChangeNotifierProvider.value(value: providers),
            ChangeNotifierProvider(create: (_) => FavoritesProvider()),
            ChangeNotifierProvider.value(value: auth),
          ],
        ),
      );
      await let(tester, providers.loadProviders);
      expect(find.text('Salon Excellence'), findsOneWidget, reason: 'C');

      unawaited(router.push('/providers'));
      await settleMocks(tester, rounds: 2);
      await tester.tap(find.text('Disponible aujourd’hui'));
      await settleMocks(tester, rounds: 2);
      expect(
        cards(tester),
        isNot(contains('provider1')),
        reason: 'C: the filter dropped it on the list',
      );
      router.pop();
      await settleMocks(tester, rounds: 2);

      expect(find.text('Salon Excellence'), findsOneWidget);
    });

    testWidgets('the home bar opens the field with the keyboard up', (
      tester,
    ) async {
      await pumpHome(tester);
      await tester.tap(find.text('Rechercher un salon…'));
      await settleMocks(tester, rounds: 2);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
    });
  });
}

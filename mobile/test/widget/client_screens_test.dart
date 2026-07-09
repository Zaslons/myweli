import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/salon_client.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_clients_provider.dart';
import 'package:myweli/screens/provider/clients/client_detail_screen.dart';
import 'package:myweli/screens/provider/clients/client_list_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_pro_clients_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Toggleable mock: the educational empty state needs a salon with no
/// clients, the rest uses the seeded base.
class _SwitchableClients extends MockProClientsService {
  bool empty = false;

  @override
  Future<ApiResponse<SalonClientsPage>> listClients(
    String providerId, {
    String? query,
    String? tag,
    int page = 1,
  }) async {
    if (empty) {
      return ApiResponse.success(
        const SalonClientsPage(items: [], page: 1, total: 0),
      );
    }
    return super.listClients(providerId, query: query, tag: tag, page: page);
  }
}

/// Module `clients` C1c (docs/design/clients-c1.md §5): the « Clients » list
/// (states, search, badges) and the client card (stats, notes).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final clients = _SwitchableClients();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proClientsService = clients;
  });

  setUp(() => clients.empty = false);

  Widget app({String initial = '/pro/clients'}) {
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/pro/clients',
          builder: (_, __) => const ClientListScreen(),
        ),
        GoRoute(
          path: '/pro/clients/:id',
          builder: (_, state) =>
              ClientDetailScreen(clientId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/pro/appointment/new',
          builder: (_, __) => const Scaffold(body: Text('MANUEL')),
        ),
      ],
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProAuthProvider()),
        ChangeNotifierProvider(create: (_) => ProClientsProvider()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// Past the mock latency without pumpAndSettle (brand loader animates
  /// forever).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    // The card loads sequentially (card → visits) — cover both mock delays.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  group('ClientListScreen', () {
    testWidgets('success: seeded clients render with badges', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);

      expect(find.text('Aïcha Koné'), findsOneWidget);
      expect(find.text('Koffi Yao'), findsOneWidget);
      // Koffi has 2 no-shows → the red badge; Aïcha is linked → MyWeli mark.
      expect(find.text('2 absences'), findsOneWidget);
      expect(find.text('MyWeli'), findsWidgets);
      // Preset tag chips are offered.
      expect(find.text('À risque'), findsOneWidget);
    });

    testWidgets('educational empty state when the base has no clients',
        (tester) async {
      clients.empty = true;
      await tester.pumpWidget(app());
      await settle(tester);

      expect(find.text('Vos clients apparaîtront ici'), findsOneWidget);
      expect(find.textContaining('première réservation'), findsOneWidget);
    });

    testWidgets('search narrows (debounced, server-side)', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, 'koffi');
      await tester.pump(const Duration(milliseconds: 350)); // debounce
      await settle(tester);

      expect(find.text('Koffi Yao'), findsOneWidget);
      expect(find.text('Aïcha Koné'), findsNothing);
    });

    testWidgets('search with no match shows the search-empty state',
        (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester);

      expect(find.text('Aucun client trouvé'), findsOneWidget);
    });

    testWidgets('tapping a row opens the card', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);

      await tester.tap(find.text('Aïcha Koné'));
      await settle(tester);

      expect(find.text('Fiche client'), findsOneWidget);
      expect(find.text('Visites'), findsOneWidget);
    });
  });

  group('ClientDetailScreen', () {
    testWidgets('card renders stats, notes and actions', (tester) async {
      await tester.pumpWidget(app(initial: '/pro/clients/sc1'));
      await settle(tester);

      expect(find.text('Aïcha Koné'), findsOneWidget);
      expect(find.text('Visites'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(
        find.text('Visible uniquement par votre équipe.'),
        findsOneWidget,
      );
      expect(
        find.text('Préfère Awa. Allergique à l’ammoniaque.'),
        findsOneWidget,
      );
      // « Nouveau rendez-vous » lives below the fold — the dedicated
      // scroll-and-tap test covers it.
    });

    testWidgets('adding a note prepends it', (tester) async {
      await tester.pumpWidget(app(initial: '/pro/clients/sc1'));
      await settle(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Ajouter une note…').first,
        'RDV souvent en retard',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Ajouter'));
      await settle(tester);

      expect(find.text('RDV souvent en retard'), findsOneWidget);
    });

    testWidgets('unknown client → introuvable state', (tester) async {
      await tester.pumpWidget(app(initial: '/pro/clients/ghost'));
      await settle(tester);

      expect(find.text('Client introuvable'), findsOneWidget);
    });

    testWidgets('« Nouveau rendez-vous » opens manual booking prefilled',
        (tester) async {
      await tester.pumpWidget(app(initial: '/pro/clients/sc1'));
      await settle(tester);

      await tester.scrollUntilVisible(
        find.text('Nouveau rendez-vous'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Nouveau rendez-vous'));
      await settle(tester);

      expect(find.text('MANUEL'), findsOneWidget);
    });
  });
}

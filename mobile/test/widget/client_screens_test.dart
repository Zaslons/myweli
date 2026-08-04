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

import '../support/pump_app.dart';

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
          builder: (_, _) => const ClientListScreen(),
        ),
        GoRoute(
          path: '/pro/clients/:id',
          builder: (_, state) =>
              ClientDetailScreen(clientId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/pro/appointment/new',
          builder: (_, _) => const Scaffold(body: Text('MANUEL')),
        ),
      ],
    );
    return wrapApp(
      providers: [
        ChangeNotifierProvider(create: (_) => ProAuthProvider()),
        ChangeNotifierProvider(create: (_) => ProClientsProvider()),
      ],
      routerConfig: router,
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

    testWidgets('educational empty state when the base has no clients', (
      tester,
    ) async {
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

    testWidgets('search with no match shows the search-empty state', (
      tester,
    ) async {
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

    /// A7-fix — **the per-funnel gate §20 claims, made real for this sheet.**
    ///
    /// `_AddClientSheet` is the exact shape that shipped four times in A7: a
    /// `FieldErrors` map declaring `name` + `phone`, both `errorText`s bound,
    /// `revalidate` wired on change — and, in the defective form, no
    /// `validate()` on submit. Because A7 also deleted the disabled-button gate
    /// (§14 rule 5 — never disable to express "invalid"), that omission is not
    /// merely silence: the press SUCCEEDS where it used to be blocked, and a
    /// nameless client with no number is written to the base.
    testWidgets(
      'the add-client sheet answers an empty submit — under both fields, '
      'and it stays open',
      (tester) async {
        await tester.pumpWidget(app());
        await settle(tester);

        await tester.tap(find.text('Ajouter un client'));
        await settle(tester);
        expect(
          find.text('Note (optionnelle)'),
          findsOneWidget,
          reason: 'the sheet is open (this label exists nowhere else)',
        );

        // Rule 5: the button is live on an empty form, so the press MUST answer.
        final submit = find.widgetWithText(ElevatedButton, 'Ajouter');
        expect(
          tester.widget<ElevatedButton>(submit).onPressed,
          isNotNull,
          reason: 'rule 5: never disabled to express "invalid"',
        );
        await tester.tap(submit);
        await settle(tester);
        await settle(tester);

        expect(
          find.text('Indiquez le nom du client.'),
          findsOneWidget,
          reason: 'the name fault renders under the name field (§14 rule 1)',
        );
        expect(
          find.text('Saisissez un numéro de téléphone.'),
          findsOneWidget,
          reason: 'and the phone fault under the phone field',
        );
        expect(
          find.byType(SnackBar),
          findsNothing,
          reason: '§14 rule 3 — a field fault is never a bar',
        );
        expect(
          find.text('Note (optionnelle)'),
          findsOneWidget,
          reason:
              'the sheet must not pop: the fields it is talking about live '
              'in it',
        );
        expect(
          find.text('Fiche client'),
          findsNothing,
          reason: 'and above all nothing was saved and nothing was opened',
        );

        // Rule 2: fixing a field clears its message without a second submit —
        // and leaves the OTHER field's message standing (FieldErrors merges).
        await tester.enterText(
          find.widgetWithText(TextField, 'Nom'),
          'Fatou Diarra',
        );
        await tester.pump();
        expect(find.text('Indiquez le nom du client.'), findsNothing);
        expect(
          find.text('Saisissez un numéro de téléphone.'),
          findsOneWidget,
          reason: 'an unfixed error survives its neighbour being fixed',
        );
      },
    );

    /// A7 changed the duplicate deliberately, and this holds the change.
    ///
    /// It used to POP the sheet, raise « Ce numéro existe déjà. » on the LIST
    /// screen, and `push` the existing card one frame later — a message about
    /// the phone field, delivered over two surfaces after the field was gone,
    /// while the navigation happened whether the user wanted it or not. The
    /// sheet keeps the message under the field now, and « Voir la fiche
    /// existante » offers the card as a choice.
    testWidgets(
      'a duplicate phone keeps the sheet open, states it under the phone '
      'field, and OFFERS the existing card',
      (tester) async {
        await tester.pumpWidget(app());
        await settle(tester);

        await tester.tap(find.text('Ajouter un client'));
        await settle(tester);

        await tester.enterText(
          find.widgetWithText(TextField, 'Nom'),
          'Aïcha K.',
        );
        await tester.pump();
        // Seeded « Aïcha Koné » is +2250700000001; the CI picker prefixes +225.
        await tester.enterText(
          find.widgetWithText(TextField, 'Numéro de téléphone'),
          '0700000001',
        );
        await tester.pump();

        await tester.tap(find.widgetWithText(ElevatedButton, 'Ajouter'));
        await settle(tester);
        await settle(tester);

        expect(
          find.text('Ce numéro existe déjà.'),
          findsOneWidget,
          reason:
              'a fault about the phone renders under the phone (§14 '
              'rule 1) — not on the screen behind, after the field has gone',
        );
        expect(
          find.byType(SnackBar),
          findsNothing,
          reason: '§14 rule 3 — a field fault is never a bar',
        );
        expect(
          find.text('Note (optionnelle)'),
          findsOneWidget,
          reason: 'the sheet stays open',
        );
        expect(
          find.text('Fiche client'),
          findsNothing,
          reason: 'and it does NOT hijack the user onto the existing card',
        );
        expect(
          find.text('Voir la fiche existante'),
          findsOneWidget,
          reason: 'the card is offered instead — rule 4, say what to DO',
        );

        // Rule 2 covers the server-set fault too: editing the number clears it,
        // and the offer goes with it (it is about the number that was typed).
        await tester.enterText(
          find.widgetWithText(TextField, 'Numéro de téléphone'),
          '0799999999',
        );
        await tester.pump();
        expect(find.text('Ce numéro existe déjà.'), findsNothing);
        expect(find.text('Voir la fiche existante'), findsNothing);
      },
    );
  });

  group('ClientDetailScreen', () {
    testWidgets('card renders stats, notes and actions', (tester) async {
      await tester.pumpWidget(app(initial: '/pro/clients/sc1'));
      await settle(tester);

      expect(find.text('Aïcha Koné'), findsOneWidget);
      expect(find.text('Visites'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Visible uniquement par votre équipe.'), findsOneWidget);
      expect(
        find.text('Préfère Awa. Allergique à l’ammoniaque.'),
        findsOneWidget,
      );
      // « Nouvelle réservation » lives below the fold — the dedicated
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

    testWidgets('« Nouvelle réservation » opens manual booking prefilled', (
      tester,
    ) async {
      await tester.pumpWidget(app(initial: '/pro/clients/sc1'));
      await settle(tester);

      await tester.scrollUntilVisible(
        find.text('Nouvelle réservation'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Nouvelle réservation'));
      await settle(tester);

      expect(find.text('MANUEL'), findsOneWidget);
    });

    /// A7-fix — the tag sheet's `errorText` was **dead**.
    ///
    /// `_tagError` was declared, rendered and cleared, but never assigned: A7
    /// wrote the block that sets it and the edit silently did not apply. All
    /// three rules therefore failed in complete silence with the « + » button
    /// ENABLED (§14 rule 5) — the user tapped and nothing whatsoever happened,
    /// which is the worst outcome the rule exists to prevent. These two tests
    /// are what makes that state unreachable again.
    Future<void> openTagSheet(WidgetTester tester) async {
      await tester.pumpWidget(app(initial: '/pro/clients/sc1'));
      await settle(tester);
      // Aïcha is seeded with « VIP », so the chip reads « Modifier ».
      await tester.tap(find.text('Modifier'));
      await settle(tester);
      expect(
        find.text('Tag personnalisé'),
        findsOneWidget,
        reason: 'the tag sheet is open',
      );
    }

    testWidgets('the tag sheet answers an empty « + » under the field', (
      tester,
    ) async {
      await openTagSheet(tester);

      await tester.tap(find.byTooltip('Ajouter le tag'));
      await settle(tester);

      expect(
        find.text('Saisissez un tag.'),
        findsOneWidget,
        reason:
            'the fault renders under the field it belongs to (§14 '
            'rule 1) — it used to be a no-op with no output at all',
      );
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: '§14 rule 3 — a field fault is never a bar',
      );
      expect(
        find.byType(FilterChip),
        findsNWidgets(3),
        reason:
            'nothing was added: the three choices are the presets '
            '(VIP · Fidèle · À risque), VIP being Aïcha’s own',
      );

      // Rule 2: typing clears it without a second press.
      await tester.enterText(
        find.widgetWithText(TextField, 'Tag personnalisé'),
        'Mariée juin',
      );
      await tester.pump();
      expect(find.text('Saisissez un tag.'), findsNothing);
    });

    testWidgets('the tag sheet answers a duplicate tag under the field', (
      tester,
    ) async {
      await openTagSheet(tester);

      // « VIP » is already on this client.
      await tester.enterText(
        find.widgetWithText(TextField, 'Tag personnalisé'),
        'VIP',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Ajouter le tag'));
      await settle(tester);

      expect(
        find.text('Ce tag est déjà ajouté.'),
        findsOneWidget,
        reason:
            'the second of the three silent rules, now spoken (§14 '
            'rule 1)',
      );
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: '§14 rule 3 — a field fault is never a bar',
      );
      expect(
        find.byType(FilterChip),
        findsNWidgets(3),
        reason: 'and no duplicate chip was appended',
      );

      // Rule 2: changing the value clears it without a second press.
      await tester.enterText(
        find.widgetWithText(TextField, 'Tag personnalisé'),
        'Mariée juin',
      );
      await tester.pump();
      expect(find.text('Ce tag est déjà ajouté.'), findsNothing);
    });
  });
}

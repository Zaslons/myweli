import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/constants/app_constants.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/text_styles.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/salon_client.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_clients_provider.dart';
import 'package:myweli/screens/provider/clients/client_detail_screen.dart';
import 'package:myweli/screens/provider/clients/client_list_screen.dart';
import 'package:myweli/services/interfaces/pro_clients_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_pro_clients_service.dart';
import 'package:myweli/widgets/common/phone_number_field.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../a11y/_a11y.dart';
import '../support/fonts.dart';
import '../support/pump_app.dart';

/// Toggleable mock: the educational empty state needs a salon with no
/// clients, the rest uses the seeded base.
///
/// It delegates to a seeded [MockProClientsService] that [reset] renews: the
/// number change (phone-leftovers.md §8) writes to the base, a test must not
/// inherit the previous one's numbers, and the locator slot this file fills is
/// `late final` — one assignment, so the double stays and its base changes.
class _SwitchableClients implements ProClientsServiceInterface {
  MockProClientsService _base = MockProClientsService();

  void reset() {
    _base = MockProClientsService();
    empty = false;
    spent = null;
    justVisited = null;
    linkedNow.clear();
    phoneAnswer = null;
    visitReads = 0;
    serverFields = null;
  }

  bool empty = false;

  /// When set, the card's « Dépensé » — the mock's own is visits × 15 000,
  /// six digits at most, and the tile's failure mode starts at seven.
  num? spent;

  @override
  Future<ApiResponse<SalonClientCard>> getCard(
    String providerId,
    String clientId,
  ) async {
    final res = await _base.getCard(providerId, clientId);
    final card = res.data;
    final fields = serverFields;
    if (card != null && fields != null) {
      final c = card.client;
      return ApiResponse.success(
        SalonClientCard.fromJson({
          'id': c.id,
          'displayName': c.displayName,
          'phone': c.phone,
          'tags': c.tags,
          'linked': c.linked,
          'stats': {
            'visits': card.stats.visits,
            'spentFcfa': card.stats.spentFcfa,
            'noShows': card.stats.noShows,
            'cancellations': card.stats.cancellations,
          },
          'notes': const <Object>[],
          ...fields,
        }),
      );
    }
    if (card != null && linkedNow.contains(clientId)) {
      final c = card.client;
      return ApiResponse.success(
        card.copyWith(
          client: SalonClient(
            id: c.id,
            displayName: c.displayName,
            phone: c.phone,
            tags: c.tags,
            lastVisitAt: c.lastVisitAt,
            linked: true,
            visits: c.visits,
            noShows: c.noShows,
          ),
        ),
      );
    }
    final override = spent;
    if (card == null || override == null) return res;
    return ApiResponse.success(
      SalonClientCard(
        client: card.client,
        stats: SalonClientStats(
          visits: card.stats.visits,
          spentFcfa: override,
          noShows: card.stats.noShows,
          cancellations: card.stats.cancellations,
        ),
        notes: card.notes,
        upcoming: card.upcoming,
      ),
    );
  }

  /// When set, the card is read from the JSON a server sends — with these
  /// fields on top: `{}` is a server from before `phoneEditable`, whose PATCH
  /// refuses a number (phone-leftovers.md §8).
  Map<String, Object?>? serverFields;

  /// Cards that were linked to an account since the screen read them — the
  /// race behind a `client_linked` answer (phone-leftovers.md §8).
  final Set<String> linkedNow = {};

  /// When set, the number change's answer (a server refusal the mock's own
  /// rule would not give, e.g. `invalid_phone` for a number the app accepts).
  ApiResponse<SalonClientPhoneChange>? phoneAnswer;

  /// How many times a card's history was read — the number change re-reads it.
  int visitReads = 0;

  @override
  Future<ApiResponse<SalonClientPhoneChange>> updatePhone(
    String providerId,
    String clientId,
    String phone,
  ) async {
    final scripted = phoneAnswer;
    if (scripted == null) {
      return _base.updatePhone(providerId, clientId, phone);
    }
    await Future<void>.delayed(AppConstants.mockDelay);
    return scripted;
  }

  @override
  Future<ApiResponse<List<Appointment>>> getVisits(
    String providerId,
    String clientId, {
    int page = 1,
  }) {
    visitReads++;
    return _base.getVisits(providerId, clientId, page: page);
  }

  @override
  Future<ApiResponse<String>> addClient(
    String providerId, {
    required String name,
    required String phone,
    String? note,
  }) => _base.addClient(providerId, name: name, phone: phone, note: note);

  @override
  Future<ApiResponse<SalonClient>> updateTags(
    String providerId,
    String clientId,
    List<String> tags,
  ) => _base.updateTags(providerId, clientId, tags);

  @override
  Future<ApiResponse<SalonClientNote>> addNote(
    String providerId,
    String clientId,
    String body,
  ) => _base.addNote(providerId, clientId, body);

  @override
  Future<ApiResponse<bool>> deleteNote(
    String providerId,
    String clientId,
    String noteId,
  ) => _base.deleteNote(providerId, clientId, noteId);

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
    final only = justVisited;
    if (only != null) {
      return ApiResponse.success(
        SalonClientsPage(items: only, page: 1, total: only.length),
      );
    }
    return _base.listClients(providerId, query: query, tag: tag, page: page);
  }

  /// When set, the whole list — clients whose last visit is a moment or a
  /// day ago (the mock's are days back, and those read as dates).
  List<SalonClient>? justVisited;
}

/// Module `clients` C1c (docs/design/clients-c1.md §5): the « Clients » list
/// (states, search, badges) and the client card (stats, notes).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final clients = _SwitchableClients();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    await loadRealFonts();
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proClientsService = clients;
  });

  // A fresh seeded base per test (see [_SwitchableClients]).
  setUp(clients.reset);

  Widget app({
    String initial = '/pro/clients',
    double scale = 1,
    bool realFonts = false,
  }) {
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
      // Real glyph widths for the layout cases only (the test font draws
      // squares); the other tests keep the default theme they were written in.
      theme: realFonts ? AppTheme.themeData(fontFamily: kRealFont) : null,
      builder: scale == 1
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
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
    // docs/design/amounts-that-fit.md §1 — the row writes the relative time
    // after « dernière », mid-sentence, and `formatRelative` hands back two
    // phrases with a capital: « dernière À l’instant », « dernière Hier ».
    testWidgets('« dernière … » reads as one phrase, without a capital', (
      tester,
    ) async {
      final now = AppClock.now();
      clients.justVisited = [
        SalonClient(
          id: 'j1',
          displayName: 'Aïcha D.',
          tags: const [],
          linked: false,
          visits: 1,
          lastVisitAt: now.subtract(const Duration(seconds: 20)),
        ),
        SalonClient(
          id: 'j2',
          displayName: 'Fatou B.',
          tags: const [],
          linked: false,
          visits: 2,
          lastVisitAt: now.subtract(const Duration(hours: 30)),
        ),
      ];
      await tester.pumpWidget(app());
      await settle(tester);
      expect(find.textContaining('dernière à l’instant'), findsOneWidget);
      expect(find.textContaining('dernière hier'), findsOneWidget);
      expect(find.textContaining('dernière À'), findsNothing);
      expect(find.textContaining('dernière Hier'), findsNothing);
    });

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

    // docs/design/pro-screenshot-shoot-fixes.md §2.1–§2.2 — found in App
    // Store screenshot 4: « dimanch / e » in the « Dernière » tile, uneven
    // tiles, and the number printed raw.
    Text valueAbove(WidgetTester tester, String label) {
      final tile = find.ancestor(
        of: find.text(label),
        matching: find.byType(Column),
      );
      return tester
          .widgetList<Text>(
            find.descendant(of: tile.first, matching: find.byType(Text)),
          )
          .first;
    }

    testWidgets('the number is grouped, in full', (tester) async {
      await tester.pumpWidget(app(initial: '/pro/clients/sc1'));
      await settle(tester);
      expect(find.text('+225 07 00 00 00 01'), findsOneWidget);
      expect(find.text('+2250700000001'), findsNothing);
    });

    // docs/design/amounts-that-fit.md §11 Q3 (owner: yes) — a phone number
    // never wraps: when it does not fit beside « Appeler » and « WhatsApp »,
    // they drop below it. It wrapped between its pairs from 1.1× on 360dp
    // (145.0dp in 136: « +225 07 00 00 » / « 00 01 »), which SYSTEM.md §13.3
    // forbids. At the default size it fits (132.2dp) and nothing moves.
    for (final width in [360.0, 393.0, 430.0]) {
      for (final scale in [1.0, 1.1, 1.3, 1.5, 2.0]) {
        testWidgets(
          'the number is on one line at ${width.toInt()}dp × $scale×',
          (tester) async {
            tester.view.physicalSize = Size(width, 2400);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              app(initial: '/pro/clients/sc1', scale: scale, realFonts: true),
            );
            await settle(tester);
            expect(tester.takeException(), isNull);

            const phone = '+225 07 00 00 00 01';
            final p = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.text(phone),
                matching: find.byType(RichText),
              ),
            );
            final oneLine = TextPainter(
              text: TextSpan(text: phone, style: p.text.style),
              textDirection: TextDirection.ltr,
              textScaler: p.textScaler,
            )..layout();
            addTearDown(oneLine.dispose);
            expect(
              p.size.height,
              closeTo(oneLine.height, 0.5),
              reason:
                  'the number needs ${oneLine.width.toStringAsFixed(1)}dp and '
                  'has ${p.size.width.toStringAsFixed(1)} — it wrapped',
            );

            // The actions stay whole and reachable, beside the number or under
            // it — never on top of it, never off the card.
            final number = tester.getRect(find.text(phone));
            for (final tip in ['Appeler', 'WhatsApp']) {
              // The IconButton, not its Tooltip: the tooltip's box is the 40dp
              // visual, the button's is the padded tap target.
              final action = tester.getRect(
                find.ancestor(
                  of: find.byTooltip(tip),
                  matching: find.byType(IconButton),
                ),
              );
              expect(action.width, greaterThanOrEqualTo(48));
              expect(action.height, greaterThanOrEqualTo(48));
              expect(
                action.left >= number.right - 0.5 ||
                    action.top >= number.bottom - 0.5,
                isTrue,
                reason: '« $tip » overlaps the number',
              );
              expect(action.right, lessThanOrEqualTo(width - 32 + 0.5));
            }
          },
        );
      }
    }

    // Where the actions are, in words: beside the name while the number
    // fits, under it when it does not.
    for (final (scale, beside) in [(1.0, true), (1.3, false)]) {
      testWidgets(
        '360dp × $scale×: the actions are ${beside ? 'beside' : 'under'} '
        'the number',
        (tester) async {
          tester.view.physicalSize = const Size(360, 2400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            app(initial: '/pro/clients/sc1', scale: scale, realFonts: true),
          );
          await settle(tester);
          final number = tester.getRect(find.text('+225 07 00 00 00 01'));
          final call = tester.getRect(find.byTooltip('Appeler'));
          expect(call.top >= number.bottom - 0.5, !beside);
        },
      );
    }

    // At 2× on 360dp the number (264dp) does not fit beside the avatar
    // either (232): it takes the card's full width, under the name.
    testWidgets('360dp × 2×: the number has the full width of the card', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(initial: '/pro/clients/sc1', scale: 2, realFonts: true),
      );
      await settle(tester);
      final number = tester.getRect(find.text('+225 07 00 00 00 01'));
      final avatar = tester.getRect(find.byType(CircleAvatar).first);
      expect(number.left, closeTo(avatar.left, 0.5), reason: 'not indented');
      expect(number.top, greaterThanOrEqualTo(avatar.bottom - 0.5));
    });

    testWidgets('« Dernière » is the compact date, never the long form', (
      tester,
    ) async {
      await tester.pumpWidget(app(initial: '/pro/clients/sc1'));
      await settle(tester);
      final value = valueAbove(tester, 'Dernière').data!;
      expect(
        value,
        matches(RegExp(r'^\d{1,2} \S+ \d{4}$')),
        reason: '« 13 oct. 2026 », not « mardi 13 octobre 2026 »',
      );
      expect(
        value,
        isNot(
          matches(
            RegExp('lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche'),
          ),
        ),
      );
    });

    // docs/design/amounts-that-fit.md §2 and §8.3 — the strip takes the widest
    // shape in which every value stays whole: 4 across → 2 × 2 → one per row.
    // Decided by measuring, so it is asserted by measuring: the guard reads
    // the rendered paragraphs (never the layout's own helper), and « widest »
    // is checked against the next shape up, token by token.
    group('the stats strip fits its amount', () {
      const labels = ['Visites', 'Dépensé', 'Absences', 'Dernière'];

      /// The tile's inner width when [n] tiles share a [width]dp screen:
      /// 16dp page padding each side, 8dp gaps, 8dp tile padding each side.
      double inner(double width, int n) => (width - 32 - (n - 1) * 8) / n - 16;

      for (final (name, spent) in [
        ('nothing', 0),
        ('4 digits', 5000),
        ('6 digits', 180000),
        ('7 digits', 1250000),
        ('9 digits', 123456789),
      ]) {
        for (final width in [360.0, 393.0, 430.0]) {
          // 1.1 is where the old constant sat: « 180 000 » needs 64.7dp of
          // a 60dp tile there, and the strip stayed four across.
          for (final scale in [1.0, 1.1, 1.3, 2.0]) {
            testWidgets('$name at ${width.toInt()}dp × $scale×', (
              tester,
            ) async {
              clients.spent = spent;
              tester.view.physicalSize = Size(width, 2400);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              await tester.pumpWidget(
                app(initial: '/pro/clients/sc1', scale: scale, realFonts: true),
              );
              await settle(tester);
              expect(tester.takeException(), isNull);
              final at = '${width.toInt()}dp × $scale×';

              // 1. Every value and label is whole.
              for (final l in labels) {
                expectNoMidWordBreak(tester, l, 'the « $l » label at $at');
                expectNoMidWordBreak(
                  tester,
                  valueAbove(tester, l).data!,
                  'the « $l » value at $at',
                );
              }

              // 2. The shape, read off the screen.
              Rect tileOf(String label) => tester.getRect(
                find
                    .ancestor(
                      of: find.text(label),
                      matching: find.byType(Container),
                    )
                    .first,
              );
              final rects = {for (final l in labels) l: tileOf(l)};
              bool sameRow(String a, String b) =>
                  rects[a]!.top < rects[b]!.bottom &&
                  rects[b]!.top < rects[a]!.bottom;
              final columns = labels
                  .where((l) => sameRow(labels.first, l))
                  .length;
              expect([4, 2, 1], contains(columns));
              expect(
                rects[labels.first]!.width,
                closeTo(inner(width, columns) + 16, 0.5),
                reason: 'the tile is as wide as $columns per row allows',
              );

              // 3. Tiles sharing a row share a height and a top.
              for (var i = 0; i < labels.length; i += columns) {
                for (final l in labels.skip(i).take(columns).skip(1)) {
                  expect(
                    rects[l]!.height,
                    closeTo(rects[labels[i]]!.height, 0.5),
                    reason: '$l and ${labels[i]} share a row at $at',
                  );
                  expect(rects[l]!.top, closeTo(rects[labels[i]]!.top, 0.5));
                }
              }

              // 4. It is the WIDEST shape that fits: one more column per row
              // would break a token. (Nine digits in one column at 2× is the
              // stated limit of §2 — it holds; beyond it nothing is promised.)
              if (columns < 4) {
                final wider = columns == 1 ? 2 : 4;
                var widest = 0.0;
                for (final l in labels) {
                  for (final text in [l, valueAbove(tester, l).data!]) {
                    final p = tester
                        .renderObjectList<RenderParagraph>(
                          find.descendant(
                            of: find.text(text),
                            matching: find.byType(RichText),
                          ),
                        )
                        .first;
                    for (final token in unbreakableTokens(text)) {
                      final tp = TextPainter(
                        text: TextSpan(text: token, style: p.text.style),
                        textDirection: TextDirection.ltr,
                        textScaler: p.textScaler,
                      )..layout();
                      if (tp.width > widest) widest = tp.width;
                      tp.dispose();
                    }
                  }
                }
                expect(
                  widest,
                  greaterThan(inner(width, wider)),
                  reason:
                      '$columns per row at $at, yet the widest token '
                      '(${widest.toStringAsFixed(1)}dp) would fit $wider per '
                      'row (${inner(width, wider).toStringAsFixed(1)}dp)',
                );
              }
            });
          }
        }
      }
    });

    // The two cases the guard pinned as known violations until the strip
    // measured (2b7301ea), now plain — and named, because the matrix above
    // says « the widest shape that fits » and a reader wants the shapes.
    for (final (what, spent, scale, expected) in [
      ('six digits at 1× stay four across', 180000, 1.0, 4),
      ('six digits at 1.1× go 2 × 2', 180000, 1.1, 2),
      ('seven digits go 2 × 2 at the default size', 1250000, 1.0, 2),
      ('nine digits at 2× go one per row', 123456789, 2.0, 1),
      ('a new client is four across at the default size', 0, 1.0, 4),
      // Not the amount this time: « Absences » itself outgrows a quarter
      // tile — what the old 1.1 constant was measured on.
      ('at 1.3× the label « Absences » alone forces 2 × 2', 0, 1.3, 2),
    ]) {
      testWidgets('360dp: $what', (tester) async {
        clients.spent = spent;
        tester.view.physicalSize = const Size(360, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          app(initial: '/pro/clients/sc1', scale: scale, realFonts: true),
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        double top(String label) => tester
            .getRect(
              find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .top;
        final first = top('Visites');
        final perRow = [
          'Visites',
          'Dépensé',
          'Absences',
          'Dernière',
        ].where((l) => (top(l) - first).abs() < 0.5).length;
        expect(perRow, expected);
        expectNoMidWordBreak(
          tester,
          valueAbove(tester, 'Dépensé').data!,
          '« Dépensé » — $what',
        );
      });
    }

    // Seen on the iPhone simulator at the default size once the price lost
    // its doubled gap (2026-10-13): « mardi 13 octobre 2026 à 08:00 » then
    // fits its line exactly and ran into the amount — « 08:007 000 FCFA ».
    // The date is an Expanded with nothing between it and the amount.
    testWidgets('in the visit history, a date and its amount do not touch', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(402, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(initial: '/pro/clients/sc1', realFonts: true),
      );
      await settle(tester);
      expect(find.text('Historique des visites'), findsOneWidget);

      final amounts = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data ?? '').endsWith('FCFA') &&
            w.style?.fontSize == AppTextStyles.bodySmall.fontSize,
      );
      expect(amounts, findsWidgets, reason: 'the mock client has visits');
      for (final e in amounts.evaluate()) {
        final amount = find.byElementPredicate((x) => x == e);
        final row = find.ancestor(of: amount, matching: find.byType(Row)).first;
        final date = find
            .descendant(of: row, matching: find.byType(Expanded))
            .first;
        expect(
          tester.getRect(amount).left - tester.getRect(date).right,
          greaterThanOrEqualTo(AppTheme.spacingS - 0.5),
          reason: 'the date column ends where the amount begins',
        );
      }
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
      // `scrollUntilVisible` stops once ANY of the button is on screen; with
      // real glyph widths (this file loads Roboto) the page is shorter and it
      // stopped with the button at y 602 on a 600 viewport — the tap missed.
      await tester.ensureVisible(find.text('Nouvelle réservation'));
      await tester.pump();
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

  // phone-leftovers.md §8 (owner, 2026-10-15) — a GUEST card's number can be
  // changed, and its history follows it (the server moves the salon's walk-ins
  // under the old number). A card linked to an account keeps the account's
  // number, read-only. A number already on another card is refused, with a way
  // to that card — never merged.
  group('ClientDetailScreen — the number', () {
    const sheetTitle = 'Modifier le numéro';
    // The tag chip reads « Modifier » too (Tante Marie has « Fidèle »): the
    // number's is the TextButton, and says what it edits to a screen reader.
    Finder editButton() => find.widgetWithText(TextButton, 'Modifier');
    Finder field() => find.descendant(
      of: find.byType(PhoneNumberField),
      matching: find.byType(TextField),
    );
    Finder save() => find.widgetWithText(ElevatedButton, 'Enregistrer');

    /// The seeded guest, « Tante Marie », +225 07 00 00 00 03 (sc3).
    Future<void> openSheet(WidgetTester tester, {double scale = 1}) async {
      await tester.pumpWidget(
        app(initial: '/pro/clients/sc3', scale: scale, realFonts: scale != 1),
      );
      await settle(tester);
      await tester.tap(editButton());
      await settle(tester);
      expect(
        find.text(sheetTitle),
        findsOneWidget,
        reason: 'the sheet is open',
      );
    }

    Future<void> submit(WidgetTester tester, String national) async {
      await tester.enterText(field(), national);
      await tester.pump();
      await tester.ensureVisible(save());
      await tester.pump();
      await tester.tap(save());
      // The PATCH, then the history (or the other card's name).
      await settle(tester);
      await settle(tester);
    }

    testWidgets('a guest card offers « Modifier » under its number; the sheet '
        'opens on that number, « Enregistrer » live', (tester) async {
      await openSheet(tester);
      expect(
        tester.widget<TextField>(field()).controller!.text,
        '0700000003',
        reason: 'prefilled with the card\'s number, under +225',
      );
      expect(
        tester.widget<ElevatedButton>(save()).onPressed,
        isNotNull,
        reason: '§14 rule 5: never disabled to express "invalid"',
      );
    });

    testWidgets('a number the rule refuses is said under the field on submit; '
        'nothing is saved and the sheet stays', (tester) async {
      await openSheet(tester);
      await tester.enterText(field(), '');
      await tester.pump();
      expect(
        find.text('Saisissez un numéro de téléphone.'),
        findsNothing,
        reason: '§14 rule 2: silent until submitted',
      );
      await tester.tap(save());
      await settle(tester);
      expect(find.text('Saisissez un numéro de téléphone.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing, reason: 'never a bar');
      expect(find.text(sheetTitle), findsOneWidget, reason: 'it stays open');

      // Rule 2: once errored, it re-validates on change.
      await tester.enterText(field(), '07000');
      await tester.pump();
      expect(
        find.text('Le numéro doit comporter 10 chiffres après +225.'),
        findsOneWidget,
      );
      await tester.enterText(field(), '0700000044');
      await tester.pump();
      expect(
        find.text('Le numéro doit comporter 10 chiffres après +225.'),
        findsNothing,
      );
    });

    testWidgets('a new number: the sheet closes, the card shows it, its visits '
        'are read again, and « Numéro mis à jour »', (tester) async {
      await openSheet(tester);
      final reads = clients.visitReads;

      await submit(tester, '0700000033');

      expect(find.text(sheetTitle), findsNothing, reason: 'the sheet closed');
      expect(find.text('+225 07 00 00 00 33'), findsOneWidget);
      expect(find.text('+225 07 00 00 00 03'), findsNothing);
      expect(
        clients.visitReads,
        reads + 1,
        reason: 'the history is read again — it follows the number',
      );
      expect(
        find.widgetWithText(SnackBar, 'Numéro mis à jour'),
        findsOneWidget,
      );
      // The count and the visit followed the number. (The history is below
      // the fold: unscrolled, « Aucune visite » is simply not built, and an
      // absence proves nothing — a mutation that left the visits behind
      // passed that way.)
      final visitsTile = find
          .ancestor(of: find.text('Visites'), matching: find.byType(Column))
          .first;
      expect(
        tester
            .widgetList<Text>(
              find.descendant(of: visitsTile, matching: find.byType(Text)),
            )
            .first
            .data,
        '1',
      );
      await tester.scrollUntilVisible(
        find.text('Historique des visites'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Historique des visites'), findsOneWidget);
      expect(find.text('Aucune visite enregistrée.'), findsNothing);
    });

    testWidgets('a number already on another card: said under the field with '
        'that client\'s name; « Ouvrir la fiche » opens that card', (
      tester,
    ) async {
      await openSheet(tester);

      await submit(tester, '0700000002'); // Koffi Yao's

      const taken = 'Ce numéro est déjà sur la fiche de Koffi Yao.';
      expect(find.text(taken), findsOneWidget, reason: 'under the field');
      expect(find.byType(SnackBar), findsNothing, reason: 'never a bar');
      expect(find.text(sheetTitle), findsOneWidget, reason: 'it stays open');
      expect(find.text('Ouvrir la fiche'), findsOneWidget);

      // Rule 2 covers the server's fault too: a changed number clears it, and
      // the offer goes with it (it was about the number that was sent).
      await tester.enterText(field(), '0700000044');
      await tester.pump();
      expect(find.text(taken), findsNothing);
      expect(find.text('Ouvrir la fiche'), findsNothing);

      await submit(tester, '0700000002');
      await tester.ensureVisible(find.text('Ouvrir la fiche'));
      await tester.pump();
      await tester.tap(find.text('Ouvrir la fiche'));
      // The sheet closes, the card is replaced, then it loads (card, visits).
      await settle(tester);
      await settle(tester);

      expect(find.text(sheetTitle), findsNothing);
      expect(find.text('Koffi Yao'), findsOneWidget, reason: 'his card');
      expect(find.text('Tante Marie'), findsNothing);
    });

    // The way a card is usually reached: pushed from the list. « Ouvrir la
    // fiche » takes the place of the card (the provider holds ONE open card —
    // a card left underneath would come back showing the other client's), so
    // « retour » lands on the list.
    testWidgets(
      'from the list: « Ouvrir la fiche » replaces the card, and back '
      'is the list',
      (tester) async {
        await tester.pumpWidget(app());
        await settle(tester);
        await tester.tap(find.text('Tante Marie'));
        await settle(tester);
        await tester.tap(editButton());
        await settle(tester);

        await submit(tester, '0700000002');
        await tester.ensureVisible(find.text('Ouvrir la fiche'));
        await tester.pump();
        await tester.tap(find.text('Ouvrir la fiche'));
        await settle(tester);
        await settle(tester);
        expect(find.text('Koffi Yao'), findsOneWidget);
        expect(find.text('Fiche client'), findsOneWidget);

        await tester.tap(find.byType(BackButton)); // « Retour » (fr)
        await settle(tester);
        expect(find.text('Fiche client'), findsNothing, reason: 'the list');
        expect(find.text('Tante Marie'), findsOneWidget);
      },
    );

    testWidgets('from the list: after a change, back on the list the row shows '
        'the new number', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);
      expect(find.textContaining('+225 07 •• •• •03'), findsOneWidget);
      await tester.tap(find.text('Tante Marie'));
      await settle(tester);
      await tester.tap(editButton());
      await settle(tester);

      await submit(tester, '0700000033');
      await tester.tap(find.byType(BackButton)); // « Retour » (fr)
      await settle(tester);

      expect(find.text('Fiche client'), findsNothing, reason: 'the list');
      expect(find.textContaining('+225 07 •• •• •33'), findsOneWidget);
      expect(find.textContaining('+225 07 •• •• •03'), findsNothing);
    });

    testWidgets('the server refuses the number (invalid_phone): its fault is '
        'under the field, in the field\'s words', (tester) async {
      clients.phoneAnswer = ApiResponse.error(
        'Numéro invalide.',
        code: 'invalid_phone',
      );
      await openSheet(tester);

      await submit(tester, '0700000044');

      expect(
        find.text('Saisissez un numéro de téléphone valide.'),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing, reason: 'never a bar');
      expect(find.text(sheetTitle), findsOneWidget, reason: 'it stays open');
    });

    testWidgets('a card linked to an account meanwhile (client_linked): the '
        'sheet closes and the card shows the account\'s number, read-only', (
      tester,
    ) async {
      clients.phoneAnswer = ApiResponse.error(
        'Numéro du compte client.',
        code: 'client_linked',
      );
      await openSheet(tester);
      clients.linkedNow.add('sc3');

      await submit(tester, '0700000044');

      expect(find.text(sheetTitle), findsNothing, reason: 'the sheet closed');
      expect(find.text('Numéro du compte client'), findsOneWidget);
      expect(editButton(), findsNothing, reason: 'nothing left to edit');
      expect(find.byType(SnackBar), findsOneWidget, reason: 'and why');
      expect(find.text('+225 07 00 00 00 03'), findsOneWidget);
    });

    testWidgets('a linked card: no « Modifier » on its number — « Numéro du '
        'compte client » under it', (tester) async {
      await tester.pumpWidget(app(initial: '/pro/clients/sc1'));
      await settle(tester);
      expect(find.text('+225 07 00 00 00 01'), findsOneWidget);
      expect(find.text('Numéro du compte client'), findsOneWidget);
      expect(editButton(), findsNothing);
      expect(
        find.text('Modifier'),
        findsOneWidget,
        reason: 'the only « Modifier » left is the tags\' chip',
      );
      final number = tester.getRect(find.text('+225 07 00 00 00 01'));
      final caption = tester.getRect(find.text('Numéro du compte client'));
      expect(caption.top, greaterThanOrEqualTo(number.bottom - 0.5));
    });

    // Which numbers the PATCH takes is the SERVER's to say (`phoneEditable` on
    // the card), not the app's to guess from `linked` and `phone`: a server
    // from before the change refuses any number (`invalid_tags` to `{phone}`),
    // and an app that guessed would offer « Modifier » to fail on every try.
    for (final (what, fields) in <(String, Map<String, Object?>)>[
      ('a server from before the flag (absent)', {}),
      ('a server that says no', {'phoneEditable': false}),
    ]) {
      testWidgets('a guest card with a number, $what: no « Modifier »', (
        tester,
      ) async {
        clients.serverFields = fields;
        await tester.pumpWidget(app(initial: '/pro/clients/sc3'));
        await settle(tester);

        expect(find.text('Tante Marie'), findsOneWidget);
        expect(find.text('+225 07 00 00 00 03'), findsOneWidget);
        expect(editButton(), findsNothing, reason: 'its PATCH takes no number');
        expect(
          find.text('Numéro du compte client'),
          findsNothing,
          reason: 'not an account\'s number either: nothing is said',
        );
      });
    }

    testWidgets('a guest card the server says is editable: « Modifier »', (
      tester,
    ) async {
      clients.serverFields = {'phoneEditable': true};
      await tester.pumpWidget(app(initial: '/pro/clients/sc3'));
      await settle(tester);

      expect(editButton(), findsOneWidget);
    });

    testWidgets(
      '« Modifier » is a 48dp target whose label says what it edits',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(app(initial: '/pro/clients/sc3'));
        await settle(tester);

        final target = tester.getRect(editButton());
        expect(target.width, greaterThanOrEqualTo(48));
        expect(target.height, greaterThanOrEqualTo(48));
        expect(
          tester.getSemantics(editButton()),
          isSemantics(
            label: 'Modifier le numéro',
            isButton: true,
            hasTapAction: true,
          ),
          reason: 'two « Modifier » on one card: the reader hears which',
        );
        final number = tester.getRect(find.text('+225 07 00 00 00 03'));
        expect(target.top, greaterThanOrEqualTo(number.bottom - 0.5));
        // The card's other targets did not lose their floor around it.
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantics.dispose();
      },
    );

    // While the number is being saved, the sheet stays — its answer is said in
    // it, or on the card it closes onto. A sheet closed under a save left the
    // late answer to pop the next route: the CARD (review, phone-leftovers).
    group('during a save', () {
      /// From the list, the way a card is usually reached: a card popped by
      /// mistake shows as the list coming back.
      Future<void> openFromList(WidgetTester tester) async {
        await tester.pumpWidget(app());
        await settle(tester);
        await tester.tap(find.text('Tante Marie'));
        await settle(tester);
        await tester.tap(editButton());
        await settle(tester);
        expect(find.text(sheetTitle), findsOneWidget);
      }

      /// Presses « Enregistrer » with [national] and stops [after] it — the
      /// mock answers the PATCH at 300 ms, the history read at 600 ms.
      Future<void> saveAndHold(
        WidgetTester tester,
        String national, {
        Duration after = const Duration(milliseconds: 100),
      }) async {
        await tester.enterText(field(), national);
        await tester.pump();
        await tester.ensureVisible(save());
        await tester.pump();
        await tester.tap(save());
        await tester.pump();
        await tester.pump(after);
      }

      /// The sheet's exit animation is 200 ms: past it, a closed sheet is
      /// gone from the tree.
      const pastExit = Duration(milliseconds: 250);

      Future<void> expectClosedOnTheCard(WidgetTester tester) async {
        await settle(tester);
        await settle(tester);
        expect(find.text(sheetTitle), findsNothing, reason: 'the answer');
        expect(find.text('Fiche client'), findsOneWidget, reason: 'the card');
        expect(find.text('+225 07 00 00 00 33'), findsOneWidget);
        expect(
          find.widgetWithText(SnackBar, 'Numéro mis à jour'),
          findsOneWidget,
        );
      }

      testWidgets('« retour » and the scrim do not close the sheet; the answer '
          'does, onto the card', (tester) async {
        await openFromList(tester);
        await saveAndHold(tester, '0700000033');

        await tester.binding.handlePopRoute(); // « retour » (Android)
        await tester.pump();
        await tester.pump(pastExit);
        expect(find.text(sheetTitle), findsOneWidget, reason: '« retour »');

        await tester.tapAt(const Offset(20, 20)); // the scrim
        await tester.pump();
        await tester.pump(pastExit);
        expect(find.text(sheetTitle), findsOneWidget, reason: 'the scrim');

        await expectClosedOnTheCard(tester);
      });

      testWidgets('a drag down does not close the sheet; the answer does', (
        tester,
      ) async {
        await openFromList(tester);
        await saveAndHold(tester, '0700000033');

        await tester.drag(find.text(sheetTitle), const Offset(0, 400));
        await tester.pump();
        await tester.pump(pastExit);
        expect(find.text(sheetTitle), findsOneWidget, reason: 'the drag');

        await expectClosedOnTheCard(tester);
      });

      testWidgets('idle, a drag down still closes the sheet', (tester) async {
        await openFromList(tester);

        await tester.drag(find.text(sheetTitle), const Offset(0, 400));
        await tester.pump();
        await tester.pump(pastExit);

        expect(find.text(sheetTitle), findsNothing);
        expect(find.text('Fiche client'), findsOneWidget);
      });

      // Any way past the sheet's own guard (a pop from code, the router):
      // the answer lands while the closed sheet is still animating out —
      // mounted — and its pop would take the next route, the card.
      testWidgets('the sheet removed under a save: its late answer leaves the '
          'card where it is', (tester) async {
        await openFromList(tester);
        await saveAndHold(
          tester,
          '0700000033',
          after: const Duration(milliseconds: 450),
        );

        Navigator.of(tester.element(find.text(sheetTitle))).pop();
        // 610 ms: the answer (600) lands inside the exit animation (to 650).
        await tester.pump(const Duration(milliseconds: 160));
        await settle(tester);

        expect(find.text(sheetTitle), findsNothing);
        expect(
          find.text('Fiche client'),
          findsOneWidget,
          reason: 'the card was not popped by the sheet\'s late answer',
        );
        expect(
          find.text('+225 07 00 00 00 33'),
          findsOneWidget,
          reason: 'the change was made all the same',
        );
      });

      testWidgets('the field is disabled while saving, and editable again '
          'with the answer', (tester) async {
        await openSheet(tester);
        await saveAndHold(tester, '0700000002'); // Koffi Yao's

        expect(
          tester.widget<TextField>(field()).enabled,
          isFalse,
          reason: 'the number being sent is the one shown',
        );

        await settle(tester);
        await settle(tester);
        expect(
          find.text('Ce numéro est déjà sur la fiche de Koffi Yao.'),
          findsOneWidget,
        );
        expect(tester.widget<TextField>(field()).enabled, isTrue);
      });

      /// An edit that reaches the sheet while the answer is out, whatever its
      /// way (the field itself is disabled then).
      void editMeanwhile(WidgetTester tester, String e164) => tester
          .widget<PhoneNumberField>(find.byType(PhoneNumberField))
          .onChanged(e164);

      testWidgets('a refusal of a number no longer in the field is not said '
          'about the one that is', (tester) async {
        await openSheet(tester);
        await saveAndHold(tester, '0700000002'); // Koffi Yao's

        editMeanwhile(tester, '+2250700000044');
        await tester.pump();
        await settle(tester);
        await settle(tester);

        expect(
          find.text('Ce numéro est déjà sur la fiche de Koffi Yao.'),
          findsNothing,
          reason: 'about 02, and the field holds 44',
        );
        expect(find.text('Ouvrir la fiche'), findsNothing);
        expect(find.text(sheetTitle), findsOneWidget);
      });

      testWidgets('a change made for a number no longer in the field does not '
          'close the sheet; the card holds it, so the field\'s is a change', (
        tester,
      ) async {
        await openSheet(tester); // the card: 03
        await saveAndHold(tester, '0700000033');

        editMeanwhile(tester, '+2250700000003'); // back to the card's
        await tester.pump();
        await settle(tester);
        await settle(tester);

        expect(find.text(sheetTitle), findsOneWidget, reason: 'stays open');
        expect(find.byType(SnackBar), findsNothing);
        expect(
          find.text('+225 07 00 00 00 33'),
          findsOneWidget,
          reason: 'the card below holds what was saved',
        );

        // 03 is no longer the card's number: saving it is a change, not
        // « nothing to change ».
        await tester.ensureVisible(save());
        await tester.pump();
        await tester.tap(save());
        await settle(tester);
        await settle(tester);

        expect(find.text(sheetTitle), findsNothing);
        expect(find.text('+225 07 00 00 00 03'), findsOneWidget);
        expect(find.text('+225 07 00 00 00 33'), findsNothing);
      });
    });

    testWidgets('the open sheet: every target ≥48dp and labelled (§13.2)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      await openSheet(tester);
      await submit(tester, '0700000002'); // the fault + « Ouvrir la fiche »
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    });

    testWidgets('the sheet at 360dp × 2: whole, its fault and both actions '
        'reachable', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const at = 'the number sheet at 360 × 2';

      await openSheet(tester, scale: 2);
      expect(tester.takeException(), isNull);

      await submit(tester, '0700000002');
      expect(tester.takeException(), isNull);

      const taken = 'Ce numéro est déjà sur la fiche de Koffi Yao.';
      expectNoMidWordBreak(tester, taken, at);
      expectNoMidWordBreak(tester, 'Ouvrir la fiche', at);
      expectNoMidWordBreak(tester, 'Enregistrer', at);
      expectNoUndeclaredTruncation(tester, context: at);

      // Both actions can be reached and pressed: the sheet scrolls.
      await tester.ensureVisible(save());
      await tester.pump();
      expect(tester.getRect(save()).bottom, lessThanOrEqualTo(780 + 0.5));
      await tester.ensureVisible(find.text('Ouvrir la fiche'));
      await tester.pump();
      await tester.tap(find.text('Ouvrir la fiche'));
      await settle(tester);
      await settle(tester);
      expect(find.text('Koffi Yao'), findsOneWidget);
    });
  });
}

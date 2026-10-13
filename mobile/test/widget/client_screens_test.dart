import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/theme/app_theme.dart';
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

import '../a11y/_a11y.dart';
import '../support/fonts.dart';
import '../support/pump_app.dart';

/// Toggleable mock: the educational empty state needs a salon with no
/// clients, the rest uses the seeded base.
class _SwitchableClients extends MockProClientsService {
  bool empty = false;

  /// When set, the card's « Dépensé » — the mock's own is visits × 15 000,
  /// six digits at most, and the tile's failure mode starts at seven.
  num? spent;

  @override
  Future<ApiResponse<SalonClientCard>> getCard(
    String providerId,
    String clientId,
  ) async {
    final res = await super.getCard(providerId, clientId);
    final card = res.data;
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
    await loadRealFonts();
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proClientsService = clients;
  });

  setUp(() {
    clients.empty = false;
    clients.spent = null;
  });

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
}

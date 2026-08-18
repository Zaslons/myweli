import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/providers/admin/admin_auth_provider.dart';
import 'package:myweli/providers/admin/admin_client_version_provider.dart';
import 'package:myweli/screens/admin/admin_client_version_screen.dart';
import 'package:myweli/services/admin/admin_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:provider/provider.dart';

import '../support/golden.dart';
import '../support/pump_app.dart';

/// The version-floors screen, and specifically its FORM behaviour.
///
/// SYSTEM.md §21 row 32 names the risk this covers: hand-rolled `errorText` is
/// "structurally uncoverable by any `FieldErrors`-based mechanism", and it is
/// "the exact shape that shipped dead in `invite_member_sheet` for months". So
/// this asserts the four things that make a form error real — it appears under
/// the field, it is NOT a snackbar, the flow does not advance, and fixing it
/// clears without a second submit.
void main() {
  late InMemorySessionStore store;

  setUpAll(loadRealFonts);

  setUp(() async {
    store = InMemorySessionStore();
    await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
  });

  Map<String, dynamic> row({int min = 0, String? url = 'https://play/x'}) => {
    'appId': 'com.myweli.app',
    'platform': 'android',
    'minimumBuild': min,
    'recommendedBuild': 0,
    'updateUrl': url,
  };

  // The real font, not the placeholder. `AppTheme.lightTheme` names no family,
  // so with nothing loaded every glyph renders as a SQUARE of the font size —
  // and « MyWeli · Admin » in squares overflows the 240dp sidebar by 62px,
  // failing every test here for a reason that has nothing to do with the
  // screen. This is a desktop surface with a fixed-width chrome, so it needs
  // real metrics the way the width gates do.
  Widget app(MockClient client) {
    final router = GoRouter(
      initialLocation: '/admin/client-version',
      routes: [
        GoRoute(
          path: '/admin/client-version',
          builder: (_, _) => const AdminClientVersionScreen(),
        ),
      ],
    );
    return wrapApp(
      providers: [
        ChangeNotifierProvider(create: (_) => AdminAuthProvider()),
        ChangeNotifierProvider(
          create: (_) => AdminClientVersionProvider(
            service: AdminService(
              client: client,
              baseUrl: 'http://x',
              store: store,
            ),
          ),
        ),
      ],
      routerConfig: router,
      theme: goldenTheme(),
    );
  }

  MockClient listing({String? url = 'https://play/x'}) => MockClient(
    (_) async => http.Response(
      jsonEncode({
        'items': [row(url: url)],
      }),
      200,
    ),
  );

  Future<void> open(WidgetTester t, MockClient client) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(app(client));
    await t.pumpAndSettle();
  }

  testWidgets('renders a row, and « manquant » when there is no link', (
    t,
  ) async {
    // The column exists for exactly this: a floor set on a row with no link is
    // a setting that silently does nothing.
    await open(t, listing(url: null));
    expect(find.text('MyWeli'), findsOneWidget);
    expect(find.text('Android'), findsOneWidget);
    expect(find.text('manquant'), findsOneWidget);
    // 0 reads as "no floor", never as a version number.
    expect(find.text('aucun'), findsWidgets);
  });

  testWidgets('a client-side fault lands UNDER THE FIELD, not in a snackbar', (
    t,
  ) async {
    await open(t, listing());
    await t.tap(find.text('Modifier'));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField).first, 'douze');
    await t.tap(find.text('Enregistrer les seuils'));
    await t.pumpAndSettle();

    expect(find.textContaining('en chiffres'), findsOneWidget);
    // The assertion that makes this a real form test rather than a smoke test.
    expect(find.byType(SnackBar), findsNothing);
    // And the flow did not advance — the dialog is still open.
    expect(find.text('Enregistrer les seuils'), findsOneWidget);
  });

  testWidgets('fixing it clears the error without a second submit', (t) async {
    await open(t, listing());
    await t.tap(find.text('Modifier'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'douze');
    await t.tap(find.text('Enregistrer les seuils'));
    await t.pumpAndSettle();
    expect(find.textContaining('en chiffres'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, '12');
    await t.pumpAndSettle();
    expect(find.textContaining('en chiffres'), findsNothing);
  });

  testWidgets('0 is accepted — it is the value meaning "no floor"', (t) async {
    // Validators.amount would reject this, which is why buildNumber exists.
    await open(t, listing());
    await t.tap(find.text('Modifier'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '0');
    await t.tap(find.text('Enregistrer les seuils'));
    await t.pumpAndSettle();
    expect(find.textContaining('Indiquez'), findsNothing);
  });

  testWidgets('a SERVER field fault also lands under its field', (t) async {
    // SYSTEM.md §830 rule 1 applies to server-side faults too — otherwise the
    // operator has to remember a toast while retyping.
    final client = MockClient((req) async {
      if (req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'items': [row()],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({'error': 'recommended_below_minimum'}),
        400,
      );
    });
    await open(t, client);
    await t.tap(find.text('Modifier'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(0), '10');
    await t.enterText(find.byType(TextField).at(1), '5');
    await t.tap(find.text('Enregistrer les seuils'));
    await t.pumpAndSettle();

    expect(find.textContaining('recommandé'), findsWidgets);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Enregistrer les seuils'), findsOneWidget);
  });
}

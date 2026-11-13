import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/providers/admin/admin_auth_provider.dart';
import 'package:myweli/providers/admin/admin_dispute_detail_provider.dart';
import 'package:myweli/providers/admin/admin_disputes_provider.dart';
import 'package:myweli/screens/admin/admin_dispute_detail_screen.dart';
import 'package:myweli/screens/admin/widgets/admin_remote_image.dart';
import 'package:myweli/services/admin/admin_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:provider/provider.dart';

import '../support/fonts.dart';
import '../support/pump_app.dart';

/// docs/design/admin-remote-images.md §4 — the dispute's deposit proof is a
/// signed link on R2: drawn by the browser, and when it fails, « Actualiser »
/// reads the dispute again, which signs a new link.
void main() {
  setUpAll(loadRealFonts);

  const proofUrl =
      'https://acc.r2.cloudflarestorage.com/deposit/u2/proof.jpg?X-Amz-Signature=s';

  Future<List<String>> open(WidgetTester t) async {
    final requests = <String>[];
    final store = InMemorySessionStore();
    await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
    final client = MockClient((req) async {
      requests.add('${req.method} ${req.url.path}');
      return http.Response(
        jsonEncode({
          'dispute': {
            'id': 'd1',
            'status': 'open',
            'reason': 'Acompte non reconnu',
            'createdAt': '2030-01-01T09:00:00.000Z',
          },
          'appointment': {
            'status': 'confirmed',
            'appointmentDate': '2030-01-02T10:00:00.000Z',
            'totalPrice': 15000,
            'clientName': 'Awa Koné',
          },
          'depositScreenshotUrl': proofUrl,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    AdminService service() =>
        AdminService(client: client, baseUrl: 'http://x', store: store);
    final router = GoRouter(
      initialLocation: '/admin/disputes/d1',
      routes: [
        GoRoute(
          path: '/admin/disputes/:id',
          builder: (_, s) =>
              AdminDisputeDetailScreen(id: s.pathParameters['id']!),
        ),
      ],
    );
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider(create: (_) => AdminAuthProvider()),
          ChangeNotifierProvider(
            create: (_) => AdminDisputeDetailProvider(service: service()),
          ),
          ChangeNotifierProvider(
            create: (_) => AdminDisputesProvider(service: service()),
          ),
        ],
        routerConfig: router,
      ),
    );
    await t.pumpAndSettle();
    // flutter_test answers the image's request 400: the refused link.
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pumpAndSettle();
    return requests;
  }

  testWidgets('the proof is drawn by the browser; a failure offers '
      '« Actualiser », which reads the dispute again', (t) async {
    final requests = await open(t);

    final proof = find.byType(AdminRemoteImage);
    expect(proof, findsOneWidget);
    expect(
      (t
                  .widget<Image>(
                    find.descendant(of: proof, matching: find.byType(Image)),
                  )
                  .image
              as NetworkImage)
          .webHtmlElementStrategy,
      WebHtmlElementStrategy.prefer,
    );
    expect(find.text(AdminRemoteImage.unavailableLabel), findsOneWidget);
    final reads = requests.where((r) => r == 'GET /admin/disputes/d1').length;
    expect(reads, 1);

    await t.tap(find.text(AdminRemoteImage.reloadLabel));
    await t.pumpAndSettle();
    expect(
      requests.where((r) => r == 'GET /admin/disputes/d1').length,
      reads + 1,
    );
  });
}

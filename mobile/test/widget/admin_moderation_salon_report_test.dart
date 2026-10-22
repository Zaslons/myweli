import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/screens/admin/widgets/admin_segmented_control.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/providers/admin/admin_auth_provider.dart';
import 'package:myweli/providers/admin/admin_moderation_provider.dart';
import 'package:myweli/screens/admin/admin_moderation_screen.dart';
import 'package:myweli/services/admin/admin_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:provider/provider.dart';

import '../support/golden.dart';
import '../support/pump_app.dart';

/// docs/design/backend-integrity-batch6.md §2.6 (B6.6, decision 20): the
/// salon's reports go to the same queue as the clients', marked « Signalé par
/// le salon » — the moderator knows who is asking.
void main() {
  setUpAll(loadRealFonts);

  Future<void> open(WidgetTester t, {required bool bySalon}) async {
    final store = InMemorySessionStore();
    await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'items': [
            {
              'reviewId': 'r1',
              'providerId': 'p1',
              'userName': 'Kouassi',
              'rating': 1,
              'text': 'Injurieux',
              'moderationStatus': 'visible',
              'reportCount': 1,
              'lastReason': 'Insultes',
              'lastReportedAt': '2026-10-21T10:00:00.000Z',
              'reportedBySalon': bySalon,
            },
          ],
          'page': 1,
          'pageSize': 20,
          'total': 1,
        }),
        200,
      ),
    );
    final router = GoRouter(
      initialLocation: '/admin/moderation',
      routes: [
        GoRoute(
          path: '/admin/moderation',
          builder: (_, _) => const AdminModerationScreen(),
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
            create: (_) => AdminModerationProvider(
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
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('a salon’s report is marked « Signalé par le salon »', (t) async {
    await open(t, bySalon: true);
    expect(find.text('Injurieux'), findsOneWidget);
    expect(find.text('Signalé par le salon'), findsOneWidget);
  });

  testWidgets('CONTROL — a client’s report is not', (t) async {
    await open(t, bySalon: false);
    expect(find.text('Injurieux'), findsOneWidget);
    expect(find.text('Signalé par le salon'), findsNothing);
  });

  testWidgets('the segments are the shared AdminSegmentedControl — one '
      'label per segment, as the shared control reads it (B7.13)', (t) async {
    await open(t, bySalon: false);
    expect(find.byType(AdminSegmentedControl), findsOneWidget);
    // The hand-rolled copy set `label:` AND drew the Text: TalkBack read
    // « Signalés » twice.
    expect(t.getSemantics(find.text('Signalés')).label, 'Signalés');
  });
}

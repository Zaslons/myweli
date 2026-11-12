import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/providers/admin/admin_auth_provider.dart';
import 'package:myweli/providers/admin/admin_kyc_provider.dart';
import 'package:myweli/screens/admin/admin_kyc_detail_screen.dart';
import 'package:myweli/screens/admin/admin_kyc_queue_screen.dart';
import 'package:myweli/services/admin/admin_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:myweli/widgets/common/timed_cached_image.dart';
import 'package:provider/provider.dart';

import '../support/golden.dart';
import '../support/pump_app.dart';

/// docs/design/admin-kyc-queue-submitted.md §1.3, §4.5–§4.7 — the KYC file in
/// the console: a PDF cannot be drawn as an image (Flutter's decoder and the
/// browser's both refuse its bytes), so it is a tile that opens the signed
/// link in a new tab; the buttons only while the file awaits review.
void main() {
  setUpAll(loadRealFonts);

  const pdfUrl = 'https://r2.test/kyc/acc1/id.pdf?sig=1';
  const jpgUrl = 'https://r2.test/kyc/acc1/selfie.jpg?sig=1';
  final t0 = DateTime.utc(2030, 1, 1, 9);

  /// The selfie carries no link by default: a network image keeps a loader
  /// spinning that no settle ends. [selfieUrl] gives it one.
  ///
  /// [pdf] false leaves the PDF out: the button tests must not depend on it
  /// (on main it went through the image widget, whose loader never settles).
  Map<String, dynamic> detail({
    Object? awaitingReview = true,
    String? selfieUrl,
    bool pdf = true,
  }) => {
    'id': 'acc1',
    'businessName': 'Salon Awa',
    'businessType': 'salon',
    'phoneNumber': '+2250700000001',
    'verificationStatus': 'pending',
    'docs': [
      if (pdf)
        {
          'type': 'idCard',
          'key': 'kyc/acc1/id.pdf',
          'viewUrl': pdfUrl,
          'format': 'pdf',
        },
      {
        'type': 'selfie',
        'key': 'kyc/acc1/selfie.jpg',
        'viewUrl': ?selfieUrl,
        'format': 'image',
      },
    ],
    'awaitingReview': ?awaitingReview,
  };

  /// What url_launcher was asked to open (its method channel, which is what
  /// a widget test reaches).
  late List<String> launched;

  setUp(() {
    launched = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            launched.add((call.arguments as Map)['url'] as String);
            return true;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        );
  });

  /// Opens the file; [responses] answers each GET of the detail in turn (the
  /// last one repeats), [approve] the POST.
  Future<List<String>> open(
    WidgetTester t, {
    required List<Map<String, dynamic>> responses,
    http.Response Function()? approve,
    double textScale = 1,
    bool settle = true,
  }) async {
    final requests = <String>[];
    var gets = 0;
    final store = InMemorySessionStore();
    await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
    final client = MockClient((req) async {
      requests.add('${req.method} ${req.url.path}');
      if (req.method == 'POST' && approve != null) return approve();
      final body = responses[gets.clamp(0, responses.length - 1)];
      gets++;
      return http.Response(jsonEncode(body), 200);
    });
    final router = GoRouter(
      initialLocation: '/admin/kyc/acc1',
      routes: [
        GoRoute(
          path: '/admin/kyc',
          builder: (_, _) => const Scaffold(body: Text('queue')),
        ),
        GoRoute(
          path: '/admin/kyc/:id',
          builder: (_, s) =>
              AdminKycDetailScreen(accountId: s.pathParameters['id']!),
        ),
      ],
    );
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    // MaterialApp builds its MediaQuery from the view: scale it there.
    t.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider(create: (_) => AdminAuthProvider()),
          ChangeNotifierProvider(
            create: (_) => AdminKycProvider(
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
    if (settle) {
      await t.pumpAndSettle();
    } else {
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
    }
    return requests;
  }

  testWidgets('a PDF is a « Document PDF » tile, never an image; the image '
      'keeps its thumbnail; both labels are French', (t) async {
    final restore = AppClock.freeze(t0);
    addTearDown(restore);
    await open(t, responses: [detail()]);

    expect(find.text('Document PDF'), findsOneWidget);
    // The PDF used to go through the image widget, and show « image not
    // available »; the selfie here has no link, so none is left.
    expect(find.byType(TimedCachedImage), findsNothing);
    expect(find.text('Pièce d’identité (CNI / passeport)'), findsOneWidget);
    expect(find.text('Photo du visage'), findsOneWidget);
    expect(find.text('idCard'), findsNothing);
    expect(
      t.getSemantics(
        find.bySemanticsLabel(
          'Ouvrir « Pièce d’identité (CNI / passeport) » (PDF) dans un '
          'nouvel onglet',
        ),
      ),
      isSemantics(isButton: true, hasTapAction: true),
    );
  });

  testWidgets('an image keeps its thumbnail (the image path is unchanged)', (
    t,
  ) async {
    final restore = AppClock.freeze(t0);
    addTearDown(restore);
    await open(t, responses: [detail(selfieUrl: jpgUrl)], settle: false);
    expect(find.byType(TimedCachedImage), findsOneWidget);
    expect(find.text('Document PDF'), findsOneWidget);
    // Dispose before the image's own 12 s timer outlives the test.
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a click opens the signed link, through url_launcher', (t) async {
    final restore = AppClock.freeze(t0);
    addTearDown(restore);
    await open(t, responses: [detail()]);

    await t.tap(find.text('Document PDF'));
    await t.pumpAndSettle();
    expect(launched, [pdfUrl]);
    expect(find.text('Impossible d’ouvrir le document.'), findsNothing);
  });

  testWidgets('past 4 min 30 s the tile reads « Lien expiré — Actualiser », '
      'and a click reloads the file instead of opening a dead link', (t) async {
    var restore = AppClock.freeze(t0);
    final requests = await open(t, responses: [detail()]);
    expect(requests.where((r) => r.startsWith('GET')), hasLength(1));

    restore();
    restore = AppClock.freeze(t0.add(const Duration(minutes: 4, seconds: 31)));
    addTearDown(() => restore());
    await t.pump(const Duration(minutes: 4, seconds: 31));
    expect(find.text('Lien expiré — Actualiser'), findsOneWidget);

    await t.tap(find.text('Lien expiré — Actualiser'));
    await t.pumpAndSettle();
    expect(launched, isEmpty);
    expect(requests.where((r) => r.startsWith('GET')), hasLength(2));
    // Fresh links: the tile opens again.
    expect(find.text('Document PDF'), findsOneWidget);
    await t.tap(find.text('Document PDF'));
    await t.pumpAndSettle();
    expect(launched, [pdfUrl]);
  });

  testWidgets('a click after the deadline reloads even if the timer is late '
      '(a background tab throttles timers)', (t) async {
    var restore = AppClock.freeze(t0);
    final requests = await open(t, responses: [detail()]);
    restore();
    // The clock moved on; no timer was allowed to fire.
    restore = AppClock.freeze(t0.add(const Duration(minutes: 6)));
    addTearDown(() => restore());

    await t.tap(find.text('Document PDF'));
    await t.pumpAndSettle();
    expect(launched, isEmpty);
    expect(requests.where((r) => r.startsWith('GET')), hasLength(2));
  });

  testWidgets('no buttons on a file that does not await review', (t) async {
    final restore = AppClock.freeze(t0);
    addTearDown(restore);
    await open(t, responses: [detail(awaitingReview: false, pdf: false)]);

    expect(find.text('Approuver'), findsNothing);
    expect(find.text('Rejeter'), findsNothing);
    expect(find.text('Aucune soumission en attente.'), findsOneWidget);
  });

  testWidgets('a backend without the field keeps the buttons', (t) async {
    final restore = AppClock.freeze(t0);
    addTearDown(restore);
    await open(t, responses: [detail(awaitingReview: null, pdf: false)]);

    expect(find.text('Approuver'), findsOneWidget);
    expect(find.text('Rejeter'), findsOneWidget);
  });

  testWidgets('a 409 says the file is no longer pending, and reloads it: the '
      'buttons give way', (t) async {
    final restore = AppClock.freeze(t0);
    addTearDown(restore);
    final requests = await open(
      t,
      responses: [
        detail(pdf: false),
        detail(awaitingReview: false, pdf: false),
      ],
      approve: () => http.Response(jsonEncode({'error': 'invalid_state'}), 409),
    );

    await t.tap(find.text('Approuver'));
    await t.pumpAndSettle();
    expect(
      find.text('Ce dossier n’est plus en attente de vérification.'),
      findsOneWidget,
    );
    expect(requests, contains('POST /admin/kyc/acc1/approve'));
    expect(requests.where((r) => r.startsWith('GET')), hasLength(2));
    expect(find.text('Approuver'), findsNothing);
    expect(find.text('Aucune soumission en attente.'), findsOneWidget);
  });

  testWidgets('at 200 % text the tile and the labels still fit', (t) async {
    // Only THIS screen's layout is judged: at 200 % the shared sidebar
    // (`admin_scaffold.dart`) overflows already, on every console screen —
    // recorded in admin-kyc-queue-submitted.md §12, not fixed here.
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      final restore = AppClock.freeze(t0);
      addTearDown(restore);
      await open(t, responses: [detail()], textScale: 2);
      expect(find.text('Document PDF'), findsOneWidget);

      final again = AppClock.freeze(t0.add(const Duration(minutes: 5)));
      addTearDown(again);
      await t.pump(const Duration(minutes: 5));
      expect(find.text('Lien expiré — Actualiser'), findsOneWidget);
    } finally {
      FlutterError.onError = previous;
    }
    final mine = errors
        .map((e) => e.toString())
        .where((e) => e.contains('admin_kyc_detail_screen.dart'))
        .toList();
    expect(mine, isEmpty);
  });

  group('the queue', () {
    Future<void> queue(WidgetTester t, Object? submittedAt) async {
      final store = InMemorySessionStore();
      await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'items': [
              {
                'accountId': 'acc1',
                'businessName': 'Salon Awa',
                'businessType': 'salon',
                'submittedAt': submittedAt,
                'docCount': 2,
              },
            ],
            'page': 1,
            'pageSize': 50,
            'total': 1,
          }),
          200,
        ),
      );
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        wrapApp(
          providers: [
            ChangeNotifierProvider(create: (_) => AdminAuthProvider()),
            ChangeNotifierProvider(
              create: (_) => AdminKycProvider(
                service: AdminService(
                  client: client,
                  baseUrl: 'http://x',
                  store: store,
                ),
              ),
            ),
          ],
          routerConfig: GoRouter(
            initialLocation: '/admin/kyc',
            routes: [
              GoRoute(
                path: '/admin/kyc',
                builder: (_, _) => const AdminKycQueueScreen(),
              ),
            ],
          ),
          theme: goldenTheme(),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('a missing submission time reads « — », not a blank', (
      t,
    ) async {
      await queue(t, null);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('a submission time reads as its date', (t) async {
      await queue(t, '2030-01-02T09:00:00.000Z');
      expect(find.text('2030-01-02'), findsOneWidget);
    });
  });
}

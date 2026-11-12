/// The admin console's screens on a fake server — for the « Salons à
/// valider » widget, a11y and golden tests (B0.18,
/// docs/design/salon-go-live-approval.md §4, §8.2).
///
/// [FakeAdminServer] answers the console's routes the way the backend builds
/// them (test/support/admin_salon_validation_fixtures.dart), or — with
/// [FakeAdminServer.oldBackend] — the way TODAY's production server does: it
/// predates B0.18, so the new routes are dart_frog's plain-text 404, the
/// overview has no `providers.pendingValidation`, and « Lever la suspension »
/// answers the whole salon (`f36963a9:backend/routes/admin/providers/[id]/
/// restore.dart` → `_setStatus` → the stored provider, no `reason` key).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/providers/admin/admin_auth_provider.dart';
import 'package:myweli/providers/admin/admin_dashboard_provider.dart';
import 'package:myweli/providers/admin/admin_disputes_provider.dart';
import 'package:myweli/providers/admin/admin_provider_detail_provider.dart';
import 'package:myweli/providers/admin/admin_providers_provider.dart';
import 'package:myweli/providers/admin/admin_salon_validation_count_provider.dart';
import 'package:myweli/providers/admin/admin_salon_validation_detail_provider.dart';
import 'package:myweli/providers/admin/admin_salon_validations_provider.dart';
import 'package:myweli/screens/admin/admin_dashboard_screen.dart';
import 'package:myweli/screens/admin/admin_provider_detail_screen.dart';
import 'package:myweli/screens/admin/admin_providers_screen.dart';
import 'package:myweli/screens/admin/admin_salon_validation_detail_screen.dart';
import 'package:myweli/screens/admin/admin_salon_validations_screen.dart';
import 'package:myweli/services/admin/admin_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'admin_salon_validation_fixtures.dart';
import 'fonts.dart';
import 'pump_app.dart';
import 'surface.dart';

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// dart_frog's answer to a route it does not have — plain text, no `error`.
http.Response routeNotFound() => http.Response('Route not found', 404);

/// The console's backend, scripted. Every field is the answer to one route;
/// [requests] records what the console asked, in order.
class FakeAdminServer {
  FakeAdminServer({this.oldBackend = false});

  /// Today's production server: before B0.18.
  final bool oldBackend;

  final requests = <http.Request>[];

  /// One answer per tab (`?state=`).
  final queue = <String, http.Response>{
    'pending': jsonResponse(queuePage()),
    'refused': jsonResponse(queuePage(items: [], total: 0)),
    'approved': jsonResponse(queuePage(items: [], total: 0)),
  };

  /// The sidebar's count (`?state=pending&pageSize=1`).
  http.Response count = jsonResponse(queuePage(total: 3));

  /// `GET /admin/salons/{id}/validation`, per id.
  final detail = <String, http.Response>{
    'provider_1': jsonResponse(detailJson()),
  };

  http.Response approve = jsonResponse({
    'salonStatus': 'active',
    'validation': validationJson(
      state: 'approved',
      wentLive: true,
      decidedAt: '2026-11-12T10:00:00.000Z',
    ),
  });

  http.Response refuse = jsonResponse({
    'validation': validationJson(
      state: 'refused',
      decidedAt: '2026-11-12T10:00:00.000Z',
      refusal: {'code': 'photos', 'note': null, 'final': false},
    ),
  });

  /// `POST /admin/providers/{id}/restore` — B0.18's `{status, reason}`.
  http.Response restore = jsonResponse({'status': 'active', 'reason': null});

  /// `GET /admin/providers` (the salons list).
  http.Response providers = jsonResponse({
    'items': [suspendedSalonRow()],
    'page': 1,
    'pageSize': 50,
    'total': 1,
  });

  /// `GET /admin/providers/{id}` (a salon's page).
  http.Response providerDetail = jsonResponse({
    ...suspendedSalonRow(),
    'recentAppointments': <Object>[],
  });

  /// `GET /admin/analytics/overview`.
  http.Response? overview;

  /// Holds the next answer to [path] until completed — a request still out.
  final _held = <String, Future<void>>{};
  void hold(String path, Future<void> until) => _held[path] = until;

  late final MockClient client = MockClient((r) async {
    requests.add(r);
    final held = _held.remove(r.url.path);
    if (held != null) await held;
    return _answer(r);
  });

  http.Response _answer(http.Request r) {
    final path = r.url.path;
    final newRoute =
        path == '/admin/salon-validations' || path.startsWith('/admin/salons/');
    if (oldBackend && newRoute) return routeNotFound();
    if (path == '/admin/salon-validations') {
      if (r.url.queryParameters['pageSize'] == '1') return count;
      return queue[r.url.queryParameters['state']] ?? routeNotFound();
    }
    final validation = RegExp(
      r'^/admin/salons/([^/]+)/validation(?:/(approve|refuse))?$',
    ).firstMatch(path);
    if (validation != null) {
      final id = Uri.decodeComponent(validation.group(1)!);
      return switch (validation.group(2)) {
        'approve' => approve,
        'refuse' => refuse,
        _ => detail[id] ?? jsonResponse({'error': 'not_found'}, 404),
      };
    }
    if (RegExp(r'^/admin/providers/[^/]+/restore$').hasMatch(path)) {
      if (oldBackend) {
        return jsonResponse({...suspendedSalonRow(), 'status': 'active'});
      }
      return restore;
    }
    if (path == '/admin/auth/login') {
      return jsonResponse({'accessToken': 'tok', 'refreshToken': 'r'});
    }
    if (path == '/admin/providers') return providers;
    if (RegExp(r'^/admin/providers/[^/]+$').hasMatch(path)) {
      return providerDetail;
    }
    if (path == '/admin/analytics/overview') {
      return overview ??
          jsonResponse({
            'providers': {
              'active': 4,
              'suspended': 1,
              if (!oldBackend) 'pendingValidation': 3,
            },
            'verification': {'pending': 2, 'verified': 5},
            'users': {'active': 10, 'banned': 0},
            'bookings': {'total': 20, 'completed': 12},
            'guardrails': {'noShowRate': 0.1, 'cancellationRate': 0.05},
            'disputes': {'open': 1},
            'reportedReviews': 0,
          });
    }
    return jsonResponse({'error': 'not_found'}, 404);
  }

  /// The requests to [path], in order.
  List<http.Request> to(String path) => [
    for (final r in requests)
      if (r.url.path == path) r,
  ];
}

/// A suspended salon as the admin providers list returns it.
Map<String, dynamic> suspendedSalonRow({String id = 'provider_9'}) => {
  'id': id,
  'name': 'Salon Suspendu',
  'commune': 'Plateau',
  'status': 'suspended',
  'featured': false,
  'rating': 4.5,
  'phoneNumber': '+2250707070707',
};

/// The providers a console screen reads, each on [server].
class ConsoleProviders {
  ConsoleProviders(FakeAdminServer server, InMemorySessionStore store)
    : service = AdminService(
        client: server.client,
        baseUrl: 'http://x',
        store: store,
      ) {
    count = AdminSalonValidationCountProvider(service: service);
    queue = AdminSalonValidationsProvider(service: service);
    detail = AdminSalonValidationDetailProvider(
      service: service,
      queue: queue,
      count: count,
    );
    providers = AdminProvidersProvider(
      service: service,
      validationCount: count,
    );
    providerDetail = AdminProviderDetailProvider(
      service: service,
      validationCount: count,
    );
    dashboard = AdminDashboardProvider(service: service);
    disputes = AdminDisputesProvider(service: service);
    auth = AdminAuthProvider(service: service);
  }

  final AdminService service;
  late final AdminSalonValidationCountProvider count;
  late final AdminSalonValidationsProvider queue;
  late final AdminSalonValidationDetailProvider detail;
  late final AdminProvidersProvider providers;
  late final AdminProviderDetailProvider providerDetail;
  late final AdminDashboardProvider dashboard;
  late final AdminDisputesProvider disputes;
  late final AdminAuthProvider auth;

  /// [withCount] false leaves the count provider out of the tree — a
  /// console (or a test) built without it: the sidebar must still render.
  List<SingleChildWidget> list({bool withCount = true}) => [
    ChangeNotifierProvider.value(value: auth),
    if (withCount) ChangeNotifierProvider.value(value: count),
    ChangeNotifierProvider.value(value: queue),
    ChangeNotifierProvider.value(value: detail),
    ChangeNotifierProvider.value(value: providers),
    ChangeNotifierProvider.value(value: providerDetail),
    ChangeNotifierProvider.value(value: dashboard),
    ChangeNotifierProvider.value(value: disputes),
  ];
}

/// A session the console's client reads its bearer from.
Future<InMemorySessionStore> signedInStore() async {
  final store = InMemorySessionStore();
  await store.save(jsonEncode({'token': 'tok', 'refreshToken': 'r'}));
  return store;
}

/// The console's routes this slice touches, on the real screens; any other
/// place is a labelled stub, so a navigation is visible in the tree.
GoRouter consoleRouter(String location) => GoRouter(
  initialLocation: location,
  routes: [
    GoRoute(
      path: '/admin/dashboard',
      builder: (_, _) => const AdminDashboardScreen(),
    ),
    GoRoute(
      path: '/admin/salon-validations',
      builder: (_, _) => const AdminSalonValidationsScreen(),
    ),
    GoRoute(
      path: '/admin/salon-validations/:id',
      builder: (_, state) => AdminSalonValidationDetailScreen(
        id: SalonId(state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/admin/providers',
      builder: (_, _) => const AdminProvidersScreen(),
    ),
    GoRoute(
      path: '/admin/providers/:id',
      builder: (_, state) =>
          AdminProviderDetailScreen(id: SalonId(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/admin/kyc/:id',
      builder: (_, state) =>
          Scaffold(body: Text('KYC ${state.pathParameters['id']}')),
    ),
  ],
);

/// The console's desktop window, and a narrow one: the `expanded` class's
/// floor (SYSTEM.md §10 — the console lives at ≥ 840dp).
const Size kConsoleWide = Size(1440, 1600);
const Size kConsoleNarrow = Size(840, 1600);

/// Pumps [location] on [server], on the real theme and font, at [size] and
/// the OS text [scale]. Returns the providers, to read and to drive.
Future<ConsoleProviders> pumpConsole(
  WidgetTester tester,
  FakeAdminServer server, {
  required String location,
  Size size = const Size(1400, 900),
  double scale = 1.0,
  bool withCount = true,
  bool settle = true,
  Future<void> Function(ConsoleProviders p)? before,
}) async {
  expect(
    realFontsLoaded,
    isTrue,
    reason: 'the console has a fixed 240dp sidebar: call loadRealFonts()',
  );
  final store = await signedInStore();
  final p = ConsoleProviders(server, store);
  if (before != null) await before(p);
  pinSurface(tester, size: size, scale: scale);
  final router = consoleRouter(location);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    wrapApp(
      providers: p.list(withCount: withCount),
      routerConfig: router,
      theme: AppTheme.themeData(fontFamily: kRealFont),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return p;
}

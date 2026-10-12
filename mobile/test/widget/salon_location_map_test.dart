import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:latlong2/latlong.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/map/map_screen.dart';
import 'package:myweli/screens/providers/provider_detail_screen.dart';
import 'package:myweli/services/interfaces/provider_service_interface.dart';
import 'package:myweli/services/mock/mock_appointment_service.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_favorites_service.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:myweli/widgets/common/carto_basemap_layer.dart';
import 'package:myweli/widgets/common/salon_map_marker.dart';
import 'package:myweli/widgets/providers/salon_location_preview.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/surface.dart';

/// The salon page's location map, and where « Voir sur la carte » leads
/// (docs/design/salon-location-map.md).
///
/// Both links pushed `/favorites?providerId=…` — renamed `/carte` on
/// 2026-08-22 (#491) — so both landed on « Page Not Found »; and the same
/// salon page is the pro « Aperçu », whose router has no map at all. These
/// pin the preview (§2.1), each app's destination (§2.2), and the map screen
/// actually centring the salon it was sent (§2.3).
void main() {
  final service = _Salons();
  final excellence = MockData.providers.firstWhere((p) => p.id == 'provider1');
  final divine = MockData.providers.firstWhere((p) => p.id == 'provider2');
  final noCoords = models.Provider.fromJson({
    ...excellence.toJson(),
    'latitude': null,
    'longitude': null,
  });

  /// Where the router is — the TOP of the stack. (`currentConfiguration.uri`
  /// keeps the base location across a `push`.)
  String locationOf(GoRouter router) => router.state.uri.toString();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    serviceLocator.providerService = service;
    serviceLocator.authService = MockAuthService();
    serviceLocator.favoritesService = MockFavoritesService();
    serviceLocator.appointmentService = MockAppointmentService();
  });

  setUp(() {
    service
      ..salon = excellence
      ..list = [excellence]
      ..byIdCalls = 0;
  });

  /// The salon page under a router. Consumer: the four consumer notifiers and
  /// a `/carte` stub. [preview]: what `/pro/apercu` mounts — ONLY
  /// ProviderProvider, seeded, and a router with no `/carte` (ProRouter has
  /// none).
  Future<GoRouter> pumpSalon(
    WidgetTester tester, {
    required models.Provider salon,
    bool preview = false,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    pinSurface(tester, size: size, scale: scale);
    service.salon = salon;
    final providers = ProviderProvider();
    AuthProvider? auth;
    if (preview) {
      providers.showPreloaded(salon);
    } else {
      // The session restores in the constructor, on a real timer.
      await tester.runAsync(() async {
        final a = AuthProvider();
        for (var i = 0; i < 60 && a.isLoading; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        auth = a;
      });
    }
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              ProviderDetailScreen(providerId: salon.id, preview: preview),
        ),
        if (!preview)
          GoRoute(
            path: '/carte',
            builder: (_, state) => Scaffold(body: Text('Carte ${state.uri}')),
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider.value(value: providers),
          if (!preview) ...[
            ChangeNotifierProvider<AuthProvider>.value(value: auth!),
            ChangeNotifierProvider(create: (_) => FavoritesProvider()),
            ChangeNotifierProvider(create: (_) => AppointmentProvider()),
          ],
        ],
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  final preview = find.byType(SalonLocationPreview);
  final addressRow = find.ancestor(
    of: find.text(excellence.address),
    matching: find.byType(InkWell),
  );

  /// « Contact » brought to a third of the way down — under the pinned
  /// toolbar, above the booking bar, so a tap lands where a thumb would.
  Future<void> showContact(WidgetTester tester) async {
    final title = find.text('Contact');
    expect(title, findsOneWidget);
    await Scrollable.ensureVisible(tester.element(title), alignment: 0.3);
    await tester.pumpAndSettle();
  }

  group('the preview (§2.1)', () {
    testWidgets('atop « Contact », above the address, 160dp, on the salon', (
      tester,
    ) async {
      await pumpSalon(tester, salon: excellence);
      await showContact(tester);

      expect(preview, findsOneWidget);
      final box = tester.getRect(preview);
      expect(box.height, SalonLocationPreview.height);
      expect(SalonLocationPreview.height, 160);
      // Below the card's title, above the address row.
      expect(box.top, greaterThan(tester.getRect(find.text('Contact')).bottom));
      expect(
        box.bottom,
        lessThan(tester.getRect(find.text(excellence.address)).top),
      );

      // The camera: on the salon, at the website's zoom 15.
      final camera = MapCamera.of(
        tester.element(
          find.descendant(of: preview, matching: find.byType(MarkerLayer)),
        ),
      );
      expect(
        camera.center,
        LatLng(excellence.latitude!, excellence.longitude!),
      );
      expect(camera.zoom, 15);

      // The map's own marker, in the salon's category; the keyed layer with no
      // pan ring; the attribution CARTO requires.
      final marker = tester.widget<SalonMapMarker>(
        find.descendant(of: preview, matching: find.byType(SalonMapMarker)),
      );
      expect(marker.category, excellence.category);
      expect(marker.isFavorite, isFalse);
      expect(
        tester
            .widget<CartoBasemapLayer>(
              find.descendant(
                of: preview,
                matching: find.byType(CartoBasemapLayer),
              ),
            )
            .panBuffer,
        0,
      );
      expect(
        find.descendant(of: preview, matching: find.byType(CartoAttribution)),
        findsOneWidget,
      );
      // Nothing to pan, pinch or zoom.
      final options = tester
          .widget<FlutterMap>(
            find.descendant(of: preview, matching: find.byType(FlutterMap)),
          )
          .options;
      expect(options.interactionOptions.flags, InteractiveFlag.none);
    });

    testWidgets('no coordinates: no map, and the address is not a link', (
      tester,
    ) async {
      final router = await pumpSalon(tester, salon: noCoords);
      await showContact(tester);

      expect(preview, findsNothing);
      expect(find.byType(FlutterMap), findsNothing);
      expect(find.text('Voir sur la carte'), findsNothing);
      expect(find.byTooltip('Itinéraire'), findsNothing);
      expect(tester.widget<InkWell>(addressRow.first).onTap, isNull);

      await tester.tap(find.text(noCoords.address));
      await tester.pumpAndSettle();
      expect(locationOf(router), '/');
      expect(find.byType(SnackBar), findsNothing, reason: 'no error to show');
    });

    testWidgets('one button for a screen reader — the website pin’s label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final router = await pumpSalon(tester, salon: excellence);
      await showContact(tester);

      final label = find.bySemanticsLabel('Voir Salon Excellence sur la carte');
      expect(
        tester.getSemantics(label),
        isSemantics(
          label: 'Voir Salon Excellence sur la carte',
          isButton: true,
          hasTapAction: true,
        ),
      );
      // Tiles, pin and the attribution button are not read one by one.
      // An IconButton's name is its TOOLTIP, not a label — so that is what
      // is searched; « Itinéraire », a tooltip outside the map, proves the
      // search can find one (a by-label search here passed with the
      // exclusion removed).
      SemanticsFinder withTooltip(String t) =>
          find.semantics.byPredicate((n) => n.tooltip == t);
      expect(withTooltip('Itinéraire'), findsOne);
      expect(withTooltip('Attributions'), findsNothing);
      expect(withTooltip('flutter_map'), findsNothing);

      // The screen reader's tap goes where a finger's does.
      tester.semantics.tap(
        find.semantics.byLabel('Voir Salon Excellence sur la carte'),
      );
      await tester.pumpAndSettle();
      expect(locationOf(router), '/carte?providerId=provider1');
      semantics.dispose();
    });

    testWidgets('a vertical drag on the map scrolls the page', (tester) async {
      final router = await pumpSalon(tester, salon: excellence);
      await showContact(tester);
      final page = Scrollable.of(tester.element(preview)).position;
      final before = page.pixels;

      await tester.drag(preview, const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(
        page.pixels,
        greaterThan(before + 100),
        reason: 'the map took the drag: it fights the page scroll',
      );
      expect(locationOf(router), '/', reason: 'a drag is not a tap');
    });

    testWidgets('200% text at 360dp: the card stays usable', (tester) async {
      await pumpSalon(
        tester,
        salon: excellence,
        size: const Size(360, 780),
        scale: 2,
      );
      await showContact(tester);

      expect(tester.takeException(), isNull);
      expect(tester.getSize(preview).height, SalonLocationPreview.height);
      expect(tester.getSize(addressRow.first).height, greaterThanOrEqualTo(48));
      // The address wraps — it is never cut.
      final address = tester.renderObject<RenderParagraph>(
        find.text(excellence.address),
      );
      expect(address.didExceedMaxLines, isFalse);
      expect(find.text('Voir sur la carte'), findsOneWidget);
      // « Itinéraire » keeps its 48dp target, inside the card.
      final directions = tester.getRect(
        find.widgetWithIcon(IconButton, Icons.directions),
      );
      expect(directions.width, greaterThanOrEqualTo(48));
      expect(directions.right, lessThanOrEqualTo(360));
    });
  });

  group('where a tap leads (§2.2)', () {
    testWidgets('consumer: the map → /carte, centred on this salon', (
      tester,
    ) async {
      final router = await pumpSalon(tester, salon: excellence);
      await showContact(tester);

      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(locationOf(router), '/carte?providerId=provider1');
      expect(find.text('Carte /carte?providerId=provider1'), findsOneWidget);
    });

    testWidgets('consumer: the address row → the same', (tester) async {
      final router = await pumpSalon(tester, salon: excellence);
      await showContact(tester);

      await tester.tap(find.text('Voir sur la carte'));
      await tester.pumpAndSettle();
      expect(locationOf(router), '/carte?providerId=provider1');
    });

    testWidgets('pro « Aperçu »: the map-app picker, never a route', (
      tester,
    ) async {
      final asked = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
          asked.add('${call.method} ${(call.arguments as Map)['url']}');
          return true;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        ),
      );
      final router = await pumpSalon(tester, salon: excellence, preview: true);
      await showContact(tester);

      for (final target in [preview, find.text('Voir sur la carte')]) {
        await tester.tap(target);
        await tester.pumpAndSettle();

        // The router never moved: the pro app has no `/carte`.
        expect(locationOf(router), '/');
        expect(find.textContaining('Page Not Found'), findsNothing);
        // The picker « Itinéraire » opens, on this salon.
        expect(find.text('Ouvrir avec'), findsOneWidget);
        expect(
          asked,
          contains(startsWith('canLaunch https://waze.com/ul?ll=5.36,-4.0083')),
        );
        Navigator.of(tester.element(find.text('Ouvrir avec'))).pop();
        await tester.pumpAndSettle();
        asked.clear();
      }
    });

    testWidgets('Mes rendez-vous « Voir sur la carte » → /carte too', (
      tester,
    ) async {
      final providers = ProviderProvider();
      await providers.loadProviders();
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: AppointmentCard(
                appointment: Appointment(
                  id: 'a1',
                  userId: 'u1',
                  providerId: 'provider1',
                  serviceIds: const [],
                  appointmentDate: DateTime(2026, 10, 20, 10),
                  status: AppointmentStatus.confirmed,
                  totalPrice: 20000,
                  createdAt: DateTime(2026),
                ),
                onTap: () {},
              ),
            ),
          ),
          GoRoute(
            path: '/carte',
            builder: (_, state) => Scaffold(body: Text('Carte ${state.uri}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        wrapApp(
          providers: [ChangeNotifierProvider.value(value: providers)],
          routerConfig: router,
        ),
      );
      await tester.pump();

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Voir sur la carte',
        ),
      );
      await tester.pumpAndSettle();
      expect(locationOf(router), '/carte?providerId=provider1');
    });
  });

  group('/carte?providerId= — the salon, its sheet open (§2.3)', () {
    const geolocator = MethodChannel('flutter.baseflow.com/geolocator');
    // Somewhere that is not the salon: Treichville.
    const userLat = 5.30;
    const userLng = -4.00;

    void locationGranted(WidgetTester tester, List<String> asked) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        geolocator,
        (call) async {
          asked.add(call.method);
          return switch (call.method) {
            'isLocationServiceEnabled' => true,
            'checkPermission' => 2, // whileInUse
            'getCurrentPosition' => {
              'latitude': userLat,
              'longitude': userLng,
              'timestamp': 0,
            },
            _ => null,
          };
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          geolocator,
          null,
        ),
      );
    }

    Future<void> pumpMap(WidgetTester tester, String focus) async {
      pinSurface(tester, size: const Size(390, 844));
      late AuthProvider auth;
      await tester.runAsync(() async {
        auth = AuthProvider();
        for (var i = 0; i < 60 && auth.isLoading; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
      await tester.pumpWidget(
        wrapApp(
          providers: [
            ChangeNotifierProvider(create: (_) => ProviderProvider()),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider(create: (_) => FavoritesProvider()),
          ],
          home: MapScreen(focusProviderId: focus),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    MapCamera cameraOf(WidgetTester tester) =>
        MapCamera.of(tester.element(find.byType(MarkerLayer)));

    int markersAt(WidgetTester tester, models.Provider p) => tester
        .widget<MarkerLayer>(find.byType(MarkerLayer))
        .markers
        .where(
          (m) =>
              m.point == LatLng(p.latitude!, p.longitude!) &&
              m.child is Semantics,
        )
        .length;

    testWidgets('a salon outside the loaded list is found, centred, opened — '
        'and the user’s position does not take the camera', (tester) async {
      final asked = <String>[];
      locationGranted(tester, asked);
      // The list (page 1 of the chosen commune) does not hold it.
      service
        ..list = [divine]
        ..salon = excellence;

      await pumpMap(tester, 'provider1');

      expect(service.byIdCalls, 1, reason: 'one public read, not in the list');
      // The sheet is up, on this salon.
      expect(find.text('Voir le salon'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Salon Excellence'),
        ),
        findsOneWidget,
      );
      // Its marker was added beside the list's one. (Read off the layer:
      // flutter_map does not build a marker outside the view.)
      expect(markersAt(tester, excellence), 1);
      expect(markersAt(tester, divine), 1);
      // The position arrived…
      expect(asked, contains('getCurrentPosition'));
      // …and the camera is still the salon's.
      expect(
        cameraOf(tester).center,
        LatLng(excellence.latitude!, excellence.longitude!),
      );
    });

    testWidgets('a salon already on screen is not fetched again', (
      tester,
    ) async {
      locationGranted(tester, []);
      service
        ..list = [excellence, divine]
        ..salon = excellence;

      await pumpMap(tester, 'provider1');

      expect(service.byIdCalls, 0);
      expect(find.text('Voir le salon'), findsOneWidget);
      expect(
        markersAt(tester, excellence),
        1,
        reason: 'no duplicate marker for a listed salon',
      );
      expect(markersAt(tester, divine), 1);
    });

    testWidgets('a salon that cannot be found says so', (tester) async {
      locationGranted(tester, []);
      service
        ..list = [divine]
        ..salon = null;

      await pumpMap(tester, 'gone');

      expect(find.text('Voir le salon'), findsNothing);
      expect(
        find.text('Ce salon n’a pas pu être affiché sur la carte.'),
        findsOneWidget,
      );
      // With nothing centred, the user's position takes the camera as before.
      expect(cameraOf(tester).center, const LatLng(userLat, userLng));
    });
  });

  test('ProviderProvider.providerForMap writes nothing', () async {
    // The salon page under the map reads these; a lookup must not move them.
    service
      ..list = []
      ..salon = excellence;
    final providers = ProviderProvider()..showPreloaded(divine);
    var notified = 0;
    providers.addListener(() => notified++);

    final found = await providers.providerForMap('provider1');

    expect(found?.id, 'provider1');
    expect(providers.selectedProvider?.id, 'provider2');
    expect(providers.isLoading, isFalse);
    expect(providers.error, isNull);
    expect(notified, 0);
    // The selected salon itself is served without a read.
    expect(await providers.providerForMap('provider2'), same(divine));
    expect(service.byIdCalls, 1);
  });
}

/// The salons the screens are given, scripted per test.
class _Salons extends MockProviderService {
  models.Provider? salon;
  List<models.Provider> list = const [];
  int byIdCalls = 0;

  @override
  Future<ApiResponse<List<models.Provider>>> getProviders({
    String? category,
    String? searchQuery,
    String? commune,
    ProviderSort sort = ProviderSort.relevance,
    bool availableToday = false,
    int page = 1,
    int limit = 20,
  }) async => ApiResponse.success(list);

  @override
  Future<ApiResponse<models.Provider>> getProviderById(String id) async {
    byIdCalls++;
    final s = salon;
    return s != null && s.id == id
        ? ApiResponse.success(s)
        : ApiResponse.error('Salon introuvable', code: 'not_found');
  }
}

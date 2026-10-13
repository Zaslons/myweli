import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:latlong2/latlong.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/theme/colors.dart';
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
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:myweli/widgets/common/salon_map_marker.dart';
import 'package:myweli/widgets/common/salon_unavailable_view.dart';
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
      ..others = const []
      ..list = [excellence]
      ..hangList = false
      ..gate = null
      ..byIdCalls = 0;
  });

  /// The salon page under a router. Consumer: the four consumer notifiers and
  /// a `/carte` stub. [preview]: what `/pro/apercu` mounts — ONLY
  /// ProviderProvider, seeded, and a router with no `/carte` (ProRouter has
  /// none).
  ///
  /// [providers]: the slot as the app left it (another salon page's salon).
  /// [settle]: false when the page is meant to stay on its loader.
  Future<GoRouter> pumpSalon(
    WidgetTester tester, {
    required models.Provider salon,
    bool preview = false,
    Size size = const Size(390, 844),
    double scale = 1,
    ProviderProvider? providers,
    bool settle = true,
  }) async {
    pinSurface(tester, size: size, scale: scale);
    service.salon = salon;
    providers ??= ProviderProvider();
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
    if (settle) await tester.pumpAndSettle();
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
      // The neutral surface the tiles arrive on — and what stays when they
      // cannot (no tile is ever fetched under `flutter test`).
      expect(options.backgroundColor, AppColors.surfaceVariant);
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
      expect(find.byTooltip(CartoAttribution.sheetTooltip), findsOneWidget);
      expect(withTooltip(CartoAttribution.sheetTooltip), findsNothing);

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

    // The review's probe: flutter_map's popup opened INSIDE the 160dp box and
    // overflowed by 56px at 1.3×, 80 at 1.5×, 220 at 2× — a FlutterError in
    // debug, the required credits cut in release. The « 200% » case above
    // never opened it.
    for (final (size, scale) in [
      (const Size(390, 844), 1.3),
      (const Size(360, 780), 2.0),
      // Wide: the test font draws every glyph a full square, so on a phone the
      // credits line alone is wider than the screen and a shrunk sheet would
      // look full width anyway. At 800dp the text no longer fills it.
      (const Size(800, 900), 1.0),
    ]) {
      testWidgets('the credits « i » at $scale×: a sheet, whole, no overflow, '
          'no navigation', (tester) async {
        final router = await pumpSalon(
          tester,
          salon: excellence,
          size: size,
          scale: scale,
        );
        await showContact(tester);
        final box = tester.getRect(preview);
        final info = find.descendant(
          of: preview,
          matching: find.byTooltip(CartoAttribution.sheetTooltip),
        );
        // The button, not its tooltip: M3 paints a 40dp disc inside the 48dp
        // target (§13.2).
        final target = tester.getRect(
          find.ancestor(of: info, matching: find.byType(IconButton)),
        );
        expect(target.width, greaterThanOrEqualTo(48), reason: '§13.2');
        expect(target.height, greaterThanOrEqualTo(48), reason: '§13.2');

        await tester.tap(info);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(locationOf(router), '/', reason: 'the « i » is not the map');
        // Nothing opened inside the box: it is still text-free and 160dp.
        expect(
          find.descendant(of: preview, matching: find.byType(Text)),
          findsNothing,
        );
        expect(tester.getRect(preview), box);
        // The credits, whole, in a sheet on screen — as wide as the screen,
        // like every sheet in the app (it shrank to its longest line and
        // floated centred until 2026-10-12).
        final sheet = find.byType(BottomSheet);
        expect(sheet, findsOneWidget);
        // The visible surface, not the BottomSheet widget: under Material 3
        // the widget centres its Material in an Align that spans the screen,
        // so the widget is full width even when the surface shrinks.
        final surface = find
            .descendant(of: sheet, matching: find.byType(Material))
            .first;
        // Full width, up to Material 3's 640dp cap for bottom sheets.
        expect(
          tester.getSize(surface).width,
          math.min(size.width, 640),
          reason: 'full width',
        );
        for (final credit in [CartoAttribution.sheetTitle, ...cartoCredits]) {
          final text = find.descendant(of: sheet, matching: find.text(credit));
          expect(text, findsOneWidget, reason: credit);
          expect(
            tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
            isFalse,
            reason: credit,
          );
          final rect = tester.getRect(text);
          expect(rect.right, lessThanOrEqualTo(size.width), reason: credit);
          expect(rect.bottom, lessThanOrEqualTo(size.height), reason: credit);
        }
        expect(cartoCredits, contains('© CARTO'));
        expect(cartoCredits, contains('© OpenStreetMap contributors'));
      });
    }
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

  const geolocator = MethodChannel('flutter.baseflow.com/geolocator');
  // Somewhere that is not the salon: Treichville.
  const userLat = 5.30;
  const userLng = -4.00;

  void locationGranted(WidgetTester tester, List<String> asked) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(geolocator, (
      call,
    ) async {
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
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        geolocator,
        null,
      ),
    );
  }

  group('/carte?providerId= — the salon, its sheet open (§2.3)', () {
    /// [providers]: what the app already holds when the map opens — the
    /// salon page's salon, a list loaded earlier. Fresh by default.
    Future<void> pumpMap(
      WidgetTester tester,
      String focus, {
      ProviderProvider? providers,
    }) async {
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
            ChangeNotifierProvider.value(
              value: providers ?? ProviderProvider(),
            ),
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

    // docs/design/salon-rating-new-and-visits-card.md §2.1 — the sheet's
    // rating is `AppRating` too: « Nouveau » for a salon nobody reviewed.
    for (final reviewed in [false, true]) {
      testWidgets(
        'the sheet\'s rating: ${reviewed ? '« ★ 4,x »' : '« Nouveau »'}',
        (tester) async {
          final asked = <String>[];
          locationGranted(tester, asked);
          service
            ..list = [divine]
            ..salon = reviewed
                ? excellence.copyWith(rating: 4.6, reviewCount: 12)
                : excellence.copyWith(rating: 0, reviewCount: 0);
          await pumpMap(tester, 'provider1');
          final inSheet = find.byType(BottomSheet);
          expect(find.text('Voir le salon'), findsOneWidget);
          Finder sheetText(String t) =>
              find.descendant(of: inSheet, matching: find.text(t));
          if (reviewed) {
            expect(sheetText('4,6'), findsOneWidget);
            expect(sheetText('Nouveau'), findsNothing);
          } else {
            expect(sheetText('Nouveau'), findsOneWidget);
            expect(sheetText('0,0'), findsNothing);
            expect(sheetText('0.0'), findsNothing);
            expect(sheetText('(0)'), findsNothing);
          }
        },
      );
    }

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

    testWidgets('the credits « i » is never under « Me localiser »', (
      tester,
    ) async {
      locationGranted(tester, []);
      service
        ..list = [divine]
        ..salon = divine;
      await pumpMap(tester, divine.id);
      // The salon sheet is up on a focused map; the corners are what matter.
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();

      final credits = tester.getRect(find.byTooltip('Attributions'));
      final locate = tester.getRect(find.byTooltip('Me localiser'));
      expect(
        credits.overlaps(locate),
        isFalse,
        reason: 'the data licence requires the « i » to be reachable',
      );
      // And it is on the map, not off it.
      final map = tester.getRect(find.byType(FlutterMap));
      expect(map.contains(credits.center), isTrue);
    });

    testWidgets('a salon already in the loaded list is not fetched again', (
      tester,
    ) async {
      locationGranted(tester, []);
      service
        ..list = [excellence, divine]
        ..salon = excellence;
      // The list the user was browsing before (it is app-wide). The map does
      // not wait for its own reload to look (§2.3), so « in the list » means
      // in memory when it opens.
      final providers = ProviderProvider();
      await providers.loadProviders();

      await pumpMap(tester, 'provider1', providers: providers);

      expect(service.byIdCalls, 0);
      expect(find.text('Voir le salon'), findsOneWidget);
      expect(
        markersAt(tester, excellence),
        1,
        reason: 'no duplicate marker for a listed salon',
      );
      expect(markersAt(tester, divine), 1);
    });

    // The review's probe: the list read never completing, the salon page's
    // salon already in hand — the camera sat on Abidjan with no sheet for as
    // long as the list took, because the focus awaited it (and the
    // favourites) first. Nothing bounds a request in time.
    testWidgets('from the salon page, the list never answering: the salon is '
        'centred and its sheet up — no network', (tester) async {
      locationGranted(tester, []);
      service
        ..hangList = true
        ..salon = excellence;
      // What the salon page beneath leaves in the shared slot.
      final providers = ProviderProvider()..showPreloaded(excellence);

      await pumpMap(tester, 'provider1', providers: providers);

      expect(providers.isLoading, isTrue, reason: 'the list is still out');
      expect(find.text('Voir le salon'), findsOneWidget);
      expect(
        cameraOf(tester).center,
        LatLng(excellence.latitude!, excellence.longitude!),
      );
      expect(cameraOf(tester).zoom, 14);
      expect(markersAt(tester, excellence), 1);
      expect(service.byIdCalls, 0, reason: 'the salon page had it');
    });

    testWidgets('not in memory, the list never answering: its one read runs '
        'alongside the list, not after it', (tester) async {
      locationGranted(tester, []);
      service
        ..hangList = true
        ..salon = excellence;

      await pumpMap(tester, 'provider1');

      expect(service.byIdCalls, 1);
      expect(find.text('Voir le salon'), findsOneWidget);
      expect(
        cameraOf(tester).center,
        LatLng(excellence.latitude!, excellence.longitude!),
      );
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

  group('a salon page shows its salon — never another (§2.7)', () {
    /// The consumer stack the review walked: salon pages, the real map, and a
    /// booking stub. Starts on salon A's page; does not settle (a page may be
    /// meant to stay on its loader).
    Future<(GoRouter, ProviderProvider)> pumpStack(WidgetTester tester) async {
      pinSurface(tester, size: const Size(390, 844));
      late AuthProvider auth;
      await tester.runAsync(() async {
        auth = AuthProvider();
        for (var i = 0; i < 60 && auth.isLoading; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
      final providers = ProviderProvider();
      final router = GoRouter(
        initialLocation: '/provider/provider1',
        routes: [
          GoRoute(
            path: '/provider/:id',
            builder: (_, state) =>
                ProviderDetailScreen(providerId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/carte',
            builder: (_, state) => MapScreen(
              focusProviderId: state.uri.queryParameters['providerId'],
            ),
          ),
          GoRoute(
            path: '/booking',
            builder: (_, state) => Scaffold(body: Text('Booking ${state.uri}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        wrapApp(
          providers: [
            ChangeNotifierProvider.value(value: providers),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider(create: (_) => FavoritesProvider()),
            ChangeNotifierProvider(create: (_) => AppointmentProvider()),
          ],
          routerConfig: router,
        ),
      );
      return (router, providers);
    }

    /// Past a route transition and the map's post-frame work, without
    /// waiting on a loader that may be meant to spin.
    Future<void> frames(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('A → its map → B → back → back: A’s page is A’s — address, '
        '« Réserver », the slot — taken back with no read', (tester) async {
      locationGranted(tester, []);
      service
        ..salon = excellence
        ..others = [divine]
        ..list = [excellence, divine];
      expect(excellence.address, isNot(divine.address));
      final (router, providers) = await pumpStack(tester);
      await frames(tester);
      expect(find.text(excellence.address), findsOneWidget);

      await showContact(tester);
      await tester.tap(preview);
      await frames(tester);
      expect(locationOf(router), '/carte?providerId=provider1');
      Navigator.of(tester.element(find.text('Voir le salon'))).pop();
      await frames(tester);

      // What the sheet's « Voir le salon » does for salon B (map_screen.dart).
      unawaited(router.push('/provider/provider2'));
      await frames(tester);
      expect(find.text(divine.address), findsOneWidget);
      // The page underneath does not take the slot back while covered: two
      // pages doing so would hand it to each other every frame.
      for (var i = 0; i < 3; i++) {
        await tester.pump();
        expect(providers.selectedProviderId, 'provider2');
      }

      router.pop();
      await frames(tester);
      expect(locationOf(router), '/carte?providerId=provider1');
      router.pop();
      await frames(tester);

      expect(locationOf(router), '/provider/provider1');
      expect(find.text(excellence.address), findsOneWidget);
      expect(find.text(divine.address), findsNothing);
      expect(providers.selectedProviderId, 'provider1');
      expect(providers.selectedProvider?.id, 'provider1');
      expect(
        service.byIdCalls,
        2,
        reason: 'A once, B once — A’s own copy, not a third read',
      );
      final book = find.text('Réserver');
      expect(book, findsOneWidget);
      await tester.tap(book);
      await frames(tester);
      expect(locationOf(router), '/booking?providerId=provider1');
    });

    testWidgets('opened while the slot holds another salon: the loader, never '
        'that salon — nor its « Réserver »', (tester) async {
      service.gate = Completer<void>(); // this page's read never answers
      await pumpSalon(
        tester,
        salon: excellence,
        // What the last salon page left.
        providers: ProviderProvider()..showPreloaded(divine),
        settle: false,
      );
      await tester.pump();
      await tester.pump();

      expect(service.byIdCalls, 1, reason: 'its read is out');
      expect(find.byType(LoadingIndicator), findsOneWidget);
      expect(find.text(divine.name), findsNothing);
      expect(find.text(divine.address), findsNothing);
      expect(find.text('Réserver'), findsNothing);
    });

    testWidgets('covered before its salon arrived: back on top, a read and the '
        'loader — never another page’s state', (tester) async {
      locationGranted(tester, []);
      service
        ..salon = excellence
        ..others = [divine]
        ..gate = Completer<void>();
      final (router, providers) = await pumpStack(tester);
      await tester.pump();
      expect(find.byType(LoadingIndicator), findsOneWidget);

      // Salon B above it before A's read answered; then both answer — A's to
      // nobody (the slot is B's by then).
      unawaited(router.push('/provider/provider2'));
      await frames(tester);
      service.gate!.complete();
      await frames(tester);
      expect(find.text(divine.address), findsOneWidget);
      expect(providers.selectedProviderId, 'provider2');

      router.pop();
      await tester.pump();
      // A has no copy: the slot's state is B's, not A's to show.
      expect(find.byType(SalonUnavailableView), findsNothing);
      await frames(tester);
      expect(find.text(excellence.address), findsOneWidget);
      expect(providers.selectedProviderId, 'provider1');
      expect(service.byIdCalls, 3, reason: 'A, B, and A again');
    });

    test('a read answered after the slot changed hands is dropped', () async {
      service
        ..others = [divine]
        ..gate = Completer<void>();
      final providers = ProviderProvider();

      final read = providers.loadProviderById('provider2');
      expect(providers.selectedProviderId, 'provider2', reason: 'before');
      // Page A takes the slot back while B's read is out.
      providers.restoreSalon(excellence);
      service.gate!.complete();
      await read;

      expect(providers.selectedProvider, same(excellence));
      expect(providers.selectedProviderId, 'provider1');
      expect(providers.isLoading, isFalse);
      expect(providers.error, isNull);
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

  /// Salons a read by id also finds, beside [salon].
  List<models.Provider> others = const [];
  List<models.Provider> list = const [];
  int byIdCalls = 0;

  /// The list read never answers — a slow network, with no timeout to end it.
  bool hangList = false;

  /// Reads by id wait for this, when set — never completed, they hang.
  Completer<void>? gate;

  @override
  Future<ApiResponse<List<models.Provider>>> getProviders({
    String? category,
    String? searchQuery,
    String? commune,
    ProviderSort sort = ProviderSort.relevance,
    bool availableToday = false,
    int page = 1,
    int limit = 20,
  }) => hangList
      ? Completer<ApiResponse<List<models.Provider>>>().future
      : Future.value(ApiResponse.success(list));

  @override
  Future<ApiResponse<models.Provider>> getProviderById(String id) async {
    byIdCalls++;
    final g = gate;
    if (g != null) await g.future;
    for (final s in [?salon, ...others]) {
      if (s.id == id) return ApiResponse.success(s);
    }
    return ApiResponse.error('Salon introuvable', code: 'not_found');
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:latlong2/latlong.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/location/location_access.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/models/provider_page.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/map/map_screen.dart';
import 'package:myweli/services/interfaces/provider_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_favorites_service.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:provider/provider.dart' hide Provider;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_location.dart';
import '../support/fonts.dart';
import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/surface.dart';

/// docs/design/consumer-location.md §2.1, §2.5, §8.1–§8.2 (A6, gap 22's
/// location half): « Carte » never opens the system dialog by itself; it
/// asks first, once; every outcome says what happened and offers the way
/// that works; the dot says what it is, and how approximate.

/// One salon, answered at once: the map's own salons are not this file's.
class _OneSalon extends MockProviderService {
  @override
  Future<ApiResponse<ProviderPage>> searchProviders(
    ProviderQuery query,
  ) async => ApiResponse.success(
    ProviderPage(items: [_salon], page: 1, pageSize: 50, total: 1),
  );

  @override
  Future<ApiResponse<List<Provider>>> getProviders({
    String? category,
    String? searchQuery,
    String? commune,
    ProviderSort sort = ProviderSort.relevance,
    bool availableToday = false,
    int page = 1,
    int limit = 20,
  }) async => ApiResponse.success(const []);

  @override
  Future<ApiResponse<Provider>> getProviderById(SalonId id) async =>
      ApiResponse.success(_salon);
}

final _salon = MockData.providers.first.copyWith(
  id: const SalonId('plateau'),
  name: 'Salon du Plateau',
  latitude: 5.325,
  longitude: -4.02,
);

const _ask = 'Voir les salons autour de vous ?';
const _refused =
    'Localisation refusée. Choisissez une commune en haut de la carte, ou '
    'autorisez-la.';
const _blocked =
    'Localisation bloquée. Autorisez-la dans les réglages du téléphone pour '
    'centrer la carte sur vous.';
const _restricted =
    'La localisation est limitée sur ce téléphone, par Temps d’écran ou un '
    'profil installé. Choisissez une commune en haut de la carte.';
const _offAndroid =
    'La localisation du téléphone est désactivée. Activez-la dans les '
    'réglages, ou choisissez une commune.';
const _offIos =
    'Le service de localisation est désactivé. Activez-le dans Réglages › '
    'Confidentialité et sécurité › Service de localisation.';
const _failed =
    'Position introuvable. Réessayez, ou choisissez une commune en haut de la '
    'carte.';

void main() {
  late FakePhoneLocation phone;

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    await loadRealFonts();
    stubSecureStorage();
    serviceLocator.providerService = _OneSalon();
    serviceLocator.authService = MockAuthService();
    serviceLocator.favoritesService = MockFavoritesService();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    phone = FakePhoneLocation();
  });

  Future<void> pumpMap(
    WidgetTester tester, {
    SalonId? focus,
    Size size = const Size(390, 844),
    double scale = 1.0,
  }) async {
    phone.install(tester);
    pinSurface(tester, size: size, scale: scale);
    late AuthProvider auth;
    await tester.runAsync(() async {
      auth = AuthProvider();
      for (var i = 0; i < 60 && auth.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });
    await tester.pumpWidget(
      wrapApp(
        theme: AppTheme.themeData(fontFamily: kRealFont),
        providers: [
          ChangeNotifierProvider(create: (_) => ProviderProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ],
        home: MapScreen(focusProviderId: focus),
      ),
    );
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(TextButton, label));
    await settle(tester);
  }

  Finder text(String t) => find.textContaining(t, findRichText: true);

  bool announced(Finder f) => find
      .ancestor(
        of: f,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.liveRegion ?? false),
        ),
      )
      .evaluate()
      .isNotEmpty;

  MapCamera camera(WidgetTester tester) =>
      tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera;

  Finder dot() => find.bySemanticsLabel('Votre position');

  Future<bool> explained() async =>
      (await SharedPreferences.getInstance()).getBool(
        LocationAccess.explainedKey,
      ) ??
      false;

  /// The banner's action buttons, by label: enabled or not.
  bool enabled(WidgetTester tester, String label) =>
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, label))
          .onPressed !=
      null;

  String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

  group('opening « Carte » (§2.1)', () {
    testWidgets('undecided, never explained: the ask banner, and NO dialog '
        '(gap 22)', (tester) async {
      await pumpMap(tester);
      expect(text(_ask), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Plus tard'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Activer'), findsOneWidget);
      expect(phone.count('requestPermission'), 0);
      expect(phone.count('getCurrentPosition'), 0);
      expect(announced(text(_ask)), isTrue);
      expect(await explained(), isFalse, reason: 'opening is not a tap');
    });

    testWidgets('undecided, already explained: nothing', (tester) async {
      SharedPreferences.setMockInitialValues({
        LocationAccess.explainedKey: true,
      });
      await pumpMap(tester);
      expect(text(_ask), findsNothing);
      expect(phone.count('requestPermission'), 0);
    });

    testWidgets('allowed: the dot, silently; no banner, no request', (
      tester,
    ) async {
      phone.check = FakePhoneLocation.whileInUse;
      await pumpMap(tester);
      expect(dot(), findsOneWidget);
      expect(text(_ask), findsNothing);
      expect(phone.count('requestPermission'), 0);
      expect(camera(tester).zoom, 13.5);
      expect(camera(tester).center.latitude, closeTo(5.30, 1e-6));
    });

    testWidgets('allowed, but the read fails: nothing at all', (tester) async {
      phone
        ..check = FakePhoneLocation.whileInUse
        ..positionError = 'LOCATION_UPDATE_FAILURE';
      await pumpMap(tester);
      expect(dot(), findsNothing);
      expect(text(_failed), findsNothing);
    });

    for (final (label, setup) in [
      ('refused for good', (FakePhoneLocation p) => p.check = 1),
      ('location off', (FakePhoneLocation p) => p.service = false),
    ]) {
      testWidgets('$label: nothing; « Me localiser » stays', (tester) async {
        setup(phone);
        await pumpMap(tester);
        expect(text(_ask), findsNothing);
        expect(text(_blocked), findsNothing);
        expect(text(_offAndroid), findsNothing);
        expect(find.byTooltip('Me localiser'), findsOneWidget);
      });
    }

    testWidgets('a salon opened: the camera stays on it', (tester) async {
      phone.check = FakePhoneLocation.whileInUse;
      await pumpMap(tester, focus: const SalonId('plateau'));
      expect(camera(tester).center.latitude, closeTo(5.325, 1e-6));
      // The position was read: the layer holds the salon and the dot. The
      // dot is off screen here (3 km from the salon, at zoom 14), where
      // flutter_map does not build it.
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
        hasLength(2),
      );
    });
  });

  group('« Activer » and its outcomes (§2.1)', () {
    testWidgets('allowed: the dot, labelled, its circle, no banner; the flag '
        'set', (tester) async {
      phone.requests = [FakePhoneLocation.whileInUse];
      await pumpMap(tester);
      await tap(tester, 'Activer');
      expect(dot(), findsOneWidget);
      final circles = tester.widget<CircleLayer>(find.byType(CircleLayer));
      expect(circles.circles.single.radius, 20);
      expect(circles.circles.single.useRadiusInMeter, isTrue);
      expect(text(_ask), findsNothing);
      expect(await explained(), isTrue);
      // Approximate is enough to centre a map (decision 275).
      expect(
        phone.positionSettings?['accuracy'],
        LocationAccuracy.medium.index,
      );
    });

    testWidgets('an approximate position: the camera frames its circle', (
      tester,
    ) async {
      phone
        ..requests = [FakePhoneLocation.whileInUse]
        ..accuracy = 3000;
      await pumpMap(tester);
      await tap(tester, 'Activer');
      final cam = camera(tester);
      // The circle's own box, 3 km each way: all of it in view.
      const dLat = 3000 / 111320.0;
      final circle = LatLngBounds(
        const LatLng(5.30 - dLat, -4.00 - dLat),
        const LatLng(5.30 + dLat, -4.00 + dLat),
      );
      expect(
        cam.visibleBounds.containsBounds(circle),
        isTrue,
        reason: 'zoom ${cam.zoom}: the circle runs off the screen',
      );
      expect(cam.zoom, lessThan(13.5));
    });

    testWidgets('refused (Android): its sentence; « Autoriser » asks again', (
      tester,
    ) async {
      phone.requests = [FakePhoneLocation.denied];
      await pumpMap(tester);
      await tap(tester, 'Activer');
      expect(text(_refused), findsOneWidget);
      expect(announced(text(_refused)), isTrue);
      expect(find.widgetWithText(TextButton, 'Fermer'), findsOneWidget);
      await tap(tester, 'Autoriser');
      expect(phone.count('requestPermission'), 2);
    });

    testWidgets('blocked: « Ouvrir les réglages » opens the APP page', (
      tester,
    ) async {
      phone.requests = [FakePhoneLocation.deniedForever];
      await pumpMap(tester);
      await tap(tester, 'Activer');
      expect(text(_blocked), findsOneWidget);
      await tap(tester, 'Ouvrir les réglages');
      expect(phone.count('openAppSettings'), 1);
      expect(phone.count('openLocationSettings'), 0);
    });

    testWidgets('location off (Android): « Ouvrir les réglages » opens the '
        'LOCATION page', (tester) async {
      SharedPreferences.setMockInitialValues({
        LocationAccess.explainedKey: true,
      });
      phone.service = false;
      await pumpMap(tester);
      await tester.tap(find.byTooltip('Me localiser'));
      await settle(tester);
      expect(text(_offAndroid), findsOneWidget);
      await tap(tester, 'Ouvrir les réglages');
      expect(phone.count('openLocationSettings'), 1);
      expect(phone.count('openAppSettings'), 0);
    });

    testWidgets('failed: « Réessayer » reads again', (tester) async {
      phone
        ..requests = [FakePhoneLocation.whileInUse]
        ..positionError = 'LOCATION_UPDATE_FAILURE';
      await pumpMap(tester);
      await tap(tester, 'Activer');
      expect(text(_failed), findsOneWidget);
      phone.positionError = null;
      await tap(tester, 'Réessayer');
      expect(phone.count('getCurrentPosition'), 2);
      expect(dot(), findsOneWidget);
      expect(text(_failed), findsNothing);
    });

    testWidgets('« Fermer » hides it until the next tap', (tester) async {
      phone.requests = [FakePhoneLocation.denied];
      await pumpMap(tester);
      await tap(tester, 'Activer');
      await tap(tester, 'Fermer');
      expect(text(_refused), findsNothing);
      expect(phone.count('requestPermission'), 1);
    });

    testWidgets('iOS: restricted and location-off say so, with no button that '
        'cannot work', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        phone.requests = [FakePhoneLocation.denied];
        await pumpMap(tester);
        await tap(tester, 'Activer');
        expect(text(_restricted), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Autoriser'), findsNothing);
        expect(
          find.widgetWithText(TextButton, 'Ouvrir les réglages'),
          findsNothing,
        );

        phone.service = false;
        await tap(tester, 'Fermer');
        await tester.tap(find.byTooltip('Me localiser'));
        await settle(tester);
        expect(text(_offIos), findsOneWidget);
        expect(
          find.widgetWithText(TextButton, 'Ouvrir les réglages'),
          findsNothing,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('one read at a time (§2.4)', () {
    testWidgets('while it runs, the banner is disabled and « Me localiser » '
        'starts nothing', (tester) async {
      phone.holdRequest = Completer<int>();
      await pumpMap(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Activer'));
      await tester.pump();
      expect(enabled(tester, 'Activer'), isFalse);
      expect(enabled(tester, 'Plus tard'), isFalse);
      await tester.tap(find.byTooltip('Me localiser'));
      await tester.pump();
      expect(phone.count('requestPermission'), 1);
      phone.holdRequest!.complete(FakePhoneLocation.whileInUse);
      await settle(tester);
      expect(dot(), findsOneWidget);
      expect(phone.count('getCurrentPosition'), 1);
    });
  });

  group('« Plus tard » (§2.1, §4)', () {
    testWidgets('hidden, the flag set, and a new map does not ask again', (
      tester,
    ) async {
      await pumpMap(tester);
      await tap(tester, 'Plus tard');
      expect(text(_ask), findsNothing);
      expect(await explained(), isTrue);
      expect(phone.count('requestPermission'), 0);

      await tester.pumpWidget(const SizedBox());
      await pumpMap(tester);
      expect(text(_ask), findsNothing);
    });
  });

  group('back from the Settings (§2.1)', () {
    Future<void> leaveAndReturn(WidgetTester tester) async {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await settle(tester);
    }

    testWidgets('allowed there: the dot, with no dialog', (tester) async {
      phone.requests = [FakePhoneLocation.deniedForever];
      await pumpMap(tester);
      await tap(tester, 'Activer');
      await tap(tester, 'Ouvrir les réglages');
      phone.check = FakePhoneLocation.whileInUse;
      await leaveAndReturn(tester);
      expect(dot(), findsOneWidget);
      expect(text(_blocked), findsNothing);
      expect(phone.count('requestPermission'), 1);
    });

    testWidgets('location turned off there: the off banner', (tester) async {
      phone.requests = [FakePhoneLocation.deniedForever];
      await pumpMap(tester);
      await tap(tester, 'Activer');
      await tap(tester, 'Ouvrir les réglages');
      phone.service = false;
      await leaveAndReturn(tester);
      expect(text(_offAndroid), findsOneWidget);
    });

    testWidgets('a resume before the app left is not the return', (
      tester,
    ) async {
      phone.requests = [FakePhoneLocation.deniedForever];
      await pumpMap(tester);
      await tap(tester, 'Activer');
      await tap(tester, 'Ouvrir les réglages');
      final before = phone.calls.length;
      phone.check = FakePhoneLocation.whileInUse;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await settle(tester);
      expect(phone.calls.length, before, reason: 'the Settings never opened');
      expect(text(_blocked), findsOneWidget);
      // It still waits for the real return.
      await leaveAndReturn(tester);
      expect(dot(), findsOneWidget);
    });

    testWidgets('a return the map did not cause (the dialog closing) reads '
        'nothing', (tester) async {
      phone.requests = [FakePhoneLocation.denied];
      await pumpMap(tester);
      await tap(tester, 'Activer');
      final before = phone.calls.length;
      phone.check = FakePhoneLocation.whileInUse;
      await leaveAndReturn(tester);
      expect(phone.calls.length, before);
      expect(dot(), findsNothing);
    });
  });

  group('focus when the focused button goes away (§2.5)', () {
    testWidgets('« Plus tard »: to « Me localiser »', (tester) async {
      await pumpMap(tester);
      await tap(tester, 'Plus tard');
      expect(focused(), 'Me localiser');
    });

    testWidgets('a banner replaced: to its way out', (tester) async {
      phone.requests = [FakePhoneLocation.deniedForever];
      await pumpMap(tester);
      await tap(tester, 'Activer');
      expect(focused(), 'location banner');
    });
  });

  group('« Me localiser »', () {
    testWidgets('with no position: the flow (the dialog follows the tap)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        LocationAccess.explainedKey: true,
      });
      phone.requests = [FakePhoneLocation.whileInUse];
      await pumpMap(tester);
      await tester.tap(find.byTooltip('Me localiser'));
      await settle(tester);
      expect(phone.count('requestPermission'), 1);
      expect(dot(), findsOneWidget);
    });

    testWidgets('with one: centres it', (tester) async {
      phone.check = FakePhoneLocation.whileInUse;
      await pumpMap(tester);
      tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!
          .move(const LatLng(5.40, -3.90), 11);
      await tester.pump();
      await tester.tap(find.byTooltip('Me localiser'));
      await settle(tester);
      expect(camera(tester).center.latitude, closeTo(5.30, 1e-6));
      expect(camera(tester).zoom, 14);
    });
  });

  group('360 dp at 200 % (§2.4, §8.2)', () {
    testWidgets('the ask banner and the blocked banner: whole, no overflow, '
        'labelled targets', (tester) async {
      phone.requests = [FakePhoneLocation.deniedForever];
      await pumpMap(tester, size: kFloorPhone, scale: 2.0);
      expect(text(_ask), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      await tap(tester, 'Activer');
      expect(text(_blocked), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final label in ['Fermer', 'Ouvrir les réglages']) {
        final rect = tester.getRect(find.widgetWithText(TextButton, label));
        expect(rect.right, lessThanOrEqualTo(kFloorPhone.width), reason: label);
      }
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}

/// The map's reads land over several frames: the status, the flag, the
/// read, the camera's post-frame move.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

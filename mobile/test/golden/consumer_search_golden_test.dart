import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/map/map_screen.dart';
import 'package:myweli/screens/providers/provider_list_screen.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_location.dart';
import '../support/frozen_clock.dart';
import '../support/golden.dart';

/// docs/design/consumer-search.md §8, « Goldens »: the salon list with a
/// text and its results, empty for a text, « Afficher plus », and the map
/// with its commune pill — each at 390 × 1× and at the floor, 360 × 200 %.
///
/// DI note (as consumer_screens_golden_test.dart): `setupDependencyInjection`
/// and nothing else; the salons a picture needs are added to `MockData` and
/// taken out after it.
void main() {
  const geolocator = MethodChannel('flutter.baseflow.com/geolocator');

  setUpAll(() async {
    AppClock.freeze(kFixedNow);
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    setupDependencyInjection();
    await loadRealFonts();
  });

  tearDownAll(AppClock.restore);

  setUp(() {
    freezeClock(kFixedNow);
    // The location goldens ask, or record the ask: each starts unasked.
    SharedPreferences.setMockInitialValues({});
  });

  /// [count] more salons in `MockData` for this picture — around Abidjan,
  /// each with a pin — and out again after it.
  void addSalons(int count) {
    final seeded = List.of(MockData.providers);
    addTearDown(
      () => MockData.providers
        ..clear()
        ..addAll(seeded),
    );
    final base = seeded[1];
    for (var i = 0; i < count; i++) {
      MockData.providers.add(
        base.copyWith(
          id: SalonId('g${'$i'.padLeft(2, '0')}'),
          name: 'Salon Akwaba ${i + 1}',
          latitude: 5.30 + (i % 8) * 0.012,
          longitude: -4.06 + (i ~/ 8) * 0.012,
        ),
      );
    }
  }

  /// [phone]: the phone's location for the map (consumer-location.md);
  /// without it, location is off and the map says nothing about it.
  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    required Size size,
    required double scale,
    FakePhoneLocation? phone,
  }) async {
    goldenSurface(tester, size: size, scale: scale);
    if (phone != null) {
      phone.install(tester);
    } else {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        geolocator,
        (call) async =>
            call.method == 'isLocationServiceEnabled' ? false : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          geolocator,
          null,
        ),
      );
    }
    late final AuthProvider auth;
    await tester.runAsync(() async {
      auth = AuthProvider();
      for (var i = 0; i < 60 && auth.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => screen)],
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProviderProvider()),
          ChangeNotifierProvider(create: (_) => AppointmentProvider()),
          ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: goldenTheme(),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('fr', 'FR')],
          locale: const Locale('fr', 'FR'),
          routerConfig: router,
        ),
      ),
    );
    await settleMocks(tester, rounds: 3);
  }

  /// The salons' photos are decoded off the fake clock. The file's first
  /// picture was taken before Beauté Divine's photo landed — a white
  /// thumbnail at 1× and the photo at 2×, where the cache already held it.
  ///
  /// Asset images only: the photos the mock seeds.
  Future<void> loadPhotos(WidgetTester tester) async {
    bool isAsset(ImageProvider p) =>
        p is AssetBundleImageProvider ||
        (p is ResizeImage && p.imageProvider is AssetBundleImageProvider);
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        final image = (element.widget as Image).image;
        if (isAsset(image)) await precacheImage(image, element);
      }
    });
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 350));
    await settleMocks(tester);
    // The caret blinks: drop the focus so no frame catches it half-drawn.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  }

  const floor = (size: Size(360, 1600), scale: 2.0, tag: '_w360_x2');
  const phone = (size: kGoldenPhone, scale: 1.0, tag: '');

  group('consumer search', () {
    for (final at in [phone, floor]) {
      testWidgets('the list, a text and its results${at.tag}', (tester) async {
        await pump(
          tester,
          const ProviderListScreen(),
          size: at.size,
          scale: at.scale,
        );
        await type(tester, 'beaute');
        expect(find.text('1 salon'), findsOneWidget);
        await loadPhotos(tester);
        await expectGolden(tester, 'consumer_search_results${at.tag}');
      });

      testWidgets('the list, empty for a text${at.tag}', (tester) async {
        await pump(
          tester,
          const ProviderListScreen(),
          size: at.size,
          scale: at.scale,
        );
        await type(tester, 'tresses');
        expect(find.text('Aucun résultat pour « tresses »'), findsOneWidget);
        await loadPhotos(tester);
        await expectGolden(tester, 'consumer_search_empty${at.tag}');
      });

      testWidgets('« Afficher plus de salons »${at.tag}', (tester) async {
        addSalons(22);
        await pump(
          tester,
          const ProviderListScreen(category: 'salon'),
          size: Size(at.size.width, at.scale == 1 ? 1200 : 2400),
          scale: at.scale,
        );
        await tester.scrollUntilVisible(
          find.text('Afficher plus de salons'),
          400,
          // The page's one vertical scroll view — the chip and filter strips
          // scroll sideways inside it.
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .first,
        );
        await tester.pump();
        await loadPhotos(tester);
        await expectGolden(tester, 'consumer_search_more${at.tag}');
      });

      testWidgets('the map, its commune pill and the 50 line${at.tag}', (
        tester,
      ) async {
        addSalons(60);
        await pump(tester, const MapScreen(), size: at.size, scale: at.scale);
        expect(
          find.text('50 salons sur 64 affichés — choisissez une commune'),
          findsOneWidget,
        );
        // No `loadPhotos`: the map shows no salon photo, and real async
        // time lets `flutter_map` open its tile cache — `path_provider`,
        // which a test does not have.
        await expectGolden(tester, 'consumer_map_commune${at.tag}');
      });

      // consumer-location.md §8.2 (A6): the map asks before any dialog,
      // says when location is blocked, and draws how approximate it is.
      testWidgets('the map asks first, with no dialog${at.tag}', (
        tester,
      ) async {
        final phone = FakePhoneLocation();
        await pump(
          tester,
          const MapScreen(),
          size: at.size,
          scale: at.scale,
          phone: phone,
        );
        await settleMocks(tester, rounds: 3);
        expect(find.text('Activer'), findsOneWidget);
        expect(phone.count('requestPermission'), 0);
        await expectGolden(tester, 'consumer_map_location_ask${at.tag}');
      });

      testWidgets('the map, location blocked${at.tag}', (tester) async {
        final phone = FakePhoneLocation()
          ..requests = [FakePhoneLocation.deniedForever];
        await pump(
          tester,
          const MapScreen(),
          size: at.size,
          scale: at.scale,
          phone: phone,
        );
        await settleMocks(tester, rounds: 3);
        await tester.tap(find.text('Activer'));
        await settleMocks(tester, rounds: 3);
        expect(find.text('Ouvrir les réglages'), findsOneWidget);
        await expectGolden(tester, 'consumer_map_location_blocked${at.tag}');
      });

      testWidgets('the map, an approximate position and its circle${at.tag}', (
        tester,
      ) async {
        final phone = FakePhoneLocation()
          ..check = FakePhoneLocation.whileInUse
          ..accuracy = 1500;
        await pump(
          tester,
          const MapScreen(),
          size: at.size,
          scale: at.scale,
          phone: phone,
        );
        await settleMocks(tester, rounds: 3);
        expect(find.bySemanticsLabel('Votre position'), findsOneWidget);
        await expectGolden(tester, 'consumer_map_location_dot${at.tag}');
      });
    }
  }, skip: kGoldensSkip);
}

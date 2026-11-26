import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/di/dependency_injection.dart';
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
import 'package:myweli/widgets/common/commune_pill.dart';
import 'package:provider/provider.dart' hide Provider;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/surface.dart';

/// docs/design/consumer-search.md §2.8 (gap 22, its A4 half): the map says
/// which commune it shows, reads its own salons — up to 50 — and has its own
/// loading, error and empty states.

/// Every map read held until the test answers it.
class _Held extends MockProviderService {
  final asked = <ProviderQuery>[];
  final answers = <Completer<ApiResponse<ProviderPage>>>[];

  @override
  Future<ApiResponse<ProviderPage>> searchProviders(ProviderQuery query) {
    asked.add(query);
    final c = Completer<ApiResponse<ProviderPage>>();
    answers.add(c);
    return c.future;
  }

  /// The home's « Près de vous » (`setCommune` reloads it): answered at
  /// once and not counted — the mock's own goes through [searchProviders].
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

  void answer(List<Provider> salons, {int? total}) => answers.last.complete(
    ApiResponse.success(
      ProviderPage(
        items: salons,
        page: 1,
        pageSize: 50,
        total: total ?? salons.length,
      ),
    ),
  );
}

Provider _at(String id, double lat) => MockData.providers.first.copyWith(
  id: SalonId(id),
  name: 'Salon $id',
  latitude: lat,
  longitude: -4.0,
);

void main() {
  final service = _Held();
  const geolocator = MethodChannel('flutter.baseflow.com/geolocator');

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    serviceLocator.providerService = service;
    serviceLocator.authService = MockAuthService();
    serviceLocator.favoritesService = MockFavoritesService();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service
      ..asked.clear()
      ..answers.clear();
  });

  late ProviderProvider providers;

  Future<void> pumpMap(WidgetTester tester, {SalonId? focus}) async {
    // Location off: the map must not wait on a position it will not get.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      geolocator,
      (call) async => switch (call.method) {
        'isLocationServiceEnabled' => false,
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        geolocator,
        null,
      ),
    );
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
          ChangeNotifierProvider.value(value: providers),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ],
        home: MapScreen(focusProviderId: focus),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> withCommune(WidgetTester tester, String? commune) async {
    providers = ProviderProvider();
    if (commune != null) {
      unawaited(providers.setCommune(commune));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  /// Whether a screen reader is told of [f] when it appears.
  bool announced(Finder f) => find
      .ancestor(
        of: f,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.liveRegion ?? false),
        ),
      )
      .evaluate()
      .isNotEmpty;

  int markers(WidgetTester tester) =>
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length;

  testWidgets('the pill names the commune; the map reads 50 of it', (
    tester,
  ) async {
    await withCommune(tester, 'Cocody');
    await pumpMap(tester);
    expect(
      find.descendant(
        of: find.byType(CommunePill),
        matching: find.text('Cocody'),
      ),
      findsOneWidget,
    );
    expect(
      service.asked.single,
      const ProviderQuery(commune: 'Cocody', pageSize: 50),
    );
  });

  testWidgets('« Toutes les communes » with none', (tester) async {
    await withCommune(tester, null);
    await pumpMap(tester);
    expect(find.text('Toutes les communes'), findsOneWidget);
    expect(service.asked.single.commune, isNull);
  });

  testWidgets('loading: a small pill, the map already there', (tester) async {
    await withCommune(tester, null);
    await pumpMap(tester);
    expect(find.text('Chargement des salons…'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    // The outcome is announced, not the wait before it (the review).
    expect(announced(find.text('Chargement des salons…')), isFalse);
    service.answer([_at('a', 5.3)]);
    await tester.pump();
    expect(find.text('Chargement des salons…'), findsNothing);
    expect(markers(tester), 1);
  });

  testWidgets('error: « Impossible d’afficher les salons. », « Réessayer »', (
    tester,
  ) async {
    await withCommune(tester, null);
    await pumpMap(tester);
    service.answers.last.complete(ApiResponse.error(kNoConnectionMessage));
    await tester.pump();
    expect(find.text('Impossible d’afficher les salons.'), findsOneWidget);
    expect(announced(find.text('Impossible d’afficher les salons.')), isTrue);
    expect(find.byType(FlutterMap), findsOneWidget, reason: 'still usable');

    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    expect(service.asked, hasLength(2));
    service.answer([_at('a', 5.3), _at('b', 5.31)]);
    await tester.pump();
    expect(find.text('Impossible d’afficher les salons.'), findsNothing);
    expect(markers(tester), 2);
  });

  testWidgets('empty in a commune: « Aucun salon à Cocody », and its way '
      'out', (tester) async {
    await withCommune(tester, 'Cocody');
    await pumpMap(tester);
    service.answer(const []);
    await tester.pump();
    expect(find.text('Aucun salon à Cocody'), findsOneWidget);

    await tester.tap(find.text('Toutes les communes').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(providers.selectedCommune, isNull);
    expect(service.asked.last.commune, isNull, reason: 'the map read again');
    service.answer(const []);
    await tester.pump();
    expect(
      find.text('Aucun salon sur la carte pour l’instant'),
      findsOneWidget,
    );
  });

  testWidgets('empty, but a focused salon is on the map: no empty banner', (
    tester,
  ) async {
    await withCommune(tester, 'Cocody');
    // The salon page beneath left its salon in the slot.
    providers.showPreloaded(MockData.providers.first);
    await pumpMap(tester, focus: MockData.providers.first.id);
    service.answer(const []);
    await tester.pump();
    await tester.pump();
    expect(find.text('Aucun salon à Cocody'), findsNothing);
  });

  testWidgets('more than 50: the line says how many, and with no commune '
      'asks for one', (tester) async {
    final fifty = [for (var i = 0; i < 50; i++) _at('m$i', 5.2 + i / 1000)];
    await withCommune(tester, null);
    await pumpMap(tester);
    service.answer(fifty, total: 63);
    await tester.pump();
    expect(
      find.text('50 salons sur 63 affichés — choisissez une commune'),
      findsOneWidget,
    );

    unawaited(providers.setCommune('Cocody'));
    await tester.pump(const Duration(milliseconds: 400));
    service.answer(fifty, total: 63);
    await tester.pump();
    expect(find.text('50 salons sur 63 à Cocody affichés'), findsOneWidget);
  });

  testWidgets('the map reads again when the commune changes — and only '
      'then', (tester) async {
    await withCommune(tester, null);
    await pumpMap(tester);
    service.answer([_at('a', 5.3)]);
    await tester.pump();

    // A salon read notifies; the commune is unchanged.
    providers
      ..showPreloaded(MockData.providers.first)
      ..clearSelectedProvider();
    await tester.pump();
    expect(service.asked, hasLength(1));

    unawaited(providers.setCommune('Marcory'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(service.asked, hasLength(2));
    expect(service.asked.last.commune, 'Marcory');
    service.answer(const []);
    await tester.pump();
  });
}

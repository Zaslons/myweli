import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/map/map_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_favorites_service.dart';
import 'package:myweli/services/mock/mock_provider_service.dart';
import 'package:myweli/widgets/common/carto_basemap_layer.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';
import '../support/secure_storage.dart';

/// The keyed CARTO layer, in a real `FlutterMap` (docs/design/map-basemap-key.md).
///
/// The assertions read what flutter_map itself would put on the wire — the
/// tile URL from the layer's own provider, the headers off that provider — so
/// a layer that builds the right strings and then fails to hand them over
/// cannot pass.
///
/// **Order matters in this file, once.** `PackageInfo` caches what it read in a
/// static, and `setMockInitialValues` writes that static with no way back; so
/// the « no platform » group runs first, before any mock is set.
void main() {
  const abidjan = TileCoordinates(1001, 993, 11);

  Widget map(Widget layer) => wrapApp(
    home: SizedBox(
      width: 400,
      height: 400,
      child: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(5.336, -4.026),
          initialZoom: 11,
        ),
        children: [layer, const CartoAttribution()],
      ),
    ),
  );

  TileLayer tileLayer(WidgetTester tester) =>
      tester.widget<TileLayer>(find.byType(TileLayer));

  String urlOf(TileLayer layer) =>
      layer.tileProvider.getTileUrl(abidjan, layer);

  void runningAs(String id) => PackageInfo.setMockInitialValues(
    appName: 'MyWeli',
    packageName: id,
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );

  group('no platform to ask (the first group — see above)', () {
    testWidgets('the layer still draws, with no restriction headers', (
      tester,
    ) async {
      await tester.pumpWidget(map(const CartoBasemapLayer(apiKey: 'k-1')));
      // The unanswered platform call fails on the REAL event loop, which
      // fake-async never advances.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      final layer = tileLayer(tester);
      expect(urlOf(layer), endsWith('/11/1001/993@2x.png?key=k-1'));
      expect(layer.tileProvider.headers, {
        'User-Agent': 'flutter_map (myweli)',
      });
    });
  });

  group('running as an app', () {
    testWidgets('the URL flutter_map fetches: rastertiles, @2x, keyed', (
      tester,
    ) async {
      runningAs('com.myweli.pro');
      await tester.pumpWidget(map(const CartoBasemapLayer(apiKey: 'k-123')));
      await tester.pump();

      expect(
        urlOf(tileLayer(tester)),
        'https://basemaps.cartocdn.com/rastertiles/light_all/11/1001/993@2x.png'
        '?key=k-123',
      );
    });

    testWidgets('every restriction header, and the real User-Agent', (
      tester,
    ) async {
      runningAs('com.myweli.pro');
      await tester.pumpWidget(map(const CartoBasemapLayer(apiKey: 'k')));
      await tester.pump();

      expect(tileLayer(tester).tileProvider.headers, {
        'X-Ios-Bundle-Identifier': 'com.myweli.pro',
        'X-Android-Package': 'com.myweli.pro',
        'X-Android-Cert': '94BE494A905B2C2ADC66AD5720EDDE124089C985',
        // Was `flutter_map (com.sadreddine.myweli)` on both screens.
        'User-Agent': 'flutter_map (com.myweli.pro)',
      });
    });

    testWidgets('and the provider caches through the watermark guard', (
      tester,
    ) async {
      runningAs('com.myweli.app');
      await tester.pumpWidget(map(const CartoBasemapLayer(apiKey: 'k')));
      await tester.pump();

      final provider = tileLayer(tester).tileProvider as NetworkTileProvider;
      expect(provider.cachingProvider, isA<CartoWatermarkRefusingCache>());
    });

    testWidgets('no key → the same URL, keyless (the visible watermark)', (
      tester,
    ) async {
      runningAs('com.myweli.app');
      // The default reads AppConfig.cartoBasemapsKey, empty under every test.
      await tester.pumpWidget(map(const CartoBasemapLayer()));
      await tester.pump();

      expect(
        urlOf(tileLayer(tester)),
        'https://basemaps.cartocdn.com/rastertiles/light_all/11/1001/993@2x.png',
      );
    });

    testWidgets('the attribution CARTO requires is on the map', (tester) async {
      runningAs('com.myweli.app');
      await tester.pumpWidget(map(const CartoBasemapLayer(apiKey: 'k')));
      await tester.pump();

      final attribution = tester.widget<RichAttributionWidget>(
        find.byType(RichAttributionWidget),
      );
      expect(
        attribution.attributions.whereType<TextSourceAttribution>().map(
          (a) => a.text,
        ),
        ['© OpenStreetMap contributors', '© CARTO'],
      );
    });

    testWidgets('the consumer « Carte » draws through it', (tester) async {
      runningAs('com.myweli.app');
      stubSecureStorage();
      serviceLocator.providerService = MockProviderService();
      serviceLocator.authService = MockAuthService();
      serviceLocator.favoritesService = MockFavoritesService();

      await tester.pumpWidget(
        wrapApp(
          providers: [
            ChangeNotifierProvider(create: (_) => ProviderProvider()),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => FavoritesProvider()),
          ],
          home: const MapScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(CartoBasemapLayer), findsOneWidget);
      expect(find.byType(CartoAttribution), findsOneWidget);
      expect(
        urlOf(tileLayer(tester)),
        startsWith('https://basemaps.cartocdn.com/rastertiles/light_all/'),
      );
      expect(
        tileLayer(tester).tileProvider.headers['X-Android-Cert'],
        'B73647C6B06001AF04D38EE2D0A5AA4722CA156F',
      );
    });
  });

  group('the watermark never reaches the device cache', () {
    CachedMapTileMetadata meta(String? etag) => CachedMapTileMetadata(
      staleAt: DateTime.utc(2100),
      lastModified: null,
      etag: etag,
    );
    final png = Uint8List.fromList([1, 2, 3]);
    const wm = '"wm-da89c20e77c1-light"';

    test('a watermark response is not stored; a real tile is', () async {
      final inner = _MemoryCache();
      final cache = CartoWatermarkRefusingCache(inner: inner);

      await cache.putTile(url: 'u1', metadata: meta(wm), bytes: png);
      await cache.putTile(url: 'u2', metadata: meta('W/"wm-x"'), bytes: png);
      await cache.putTile(url: 'u3', metadata: meta('"real"'), bytes: png);

      expect(inner.tiles.keys, ['u3']);
    });

    test('a watermark already on disk counts as absent', () async {
      final inner = _MemoryCache()
        ..tiles['old'] = (bytes: png, metadata: meta(wm))
        ..tiles['good'] = (bytes: png, metadata: meta('"real"'));
      final cache = CartoWatermarkRefusingCache(inner: inner);

      expect(await cache.getTile('old'), isNull);
      expect((await cache.getTile('good'))?.metadata.etag, '"real"');
      expect(await cache.getTile('missing'), isNull);
    });

    test('support is the built-in cache\'s to decide', () {
      expect(
        CartoWatermarkRefusingCache(inner: _MemoryCache()).isSupported,
        isTrue,
      );
      expect(
        CartoWatermarkRefusingCache(
          inner: _MemoryCache(supported: false),
        ).isSupported,
        isFalse,
      );
    });
  });

  group('every app map goes through the one keyed layer', () {
    /// Code only: full-line comments and trailing ` //` comments removed —
    /// `https://` survives because its `//` follows a colon.
    String code(String src) => src
        .split('\n')
        .map((l) {
          if (l.trimLeft().startsWith('//')) return '';
          final trailing = l.indexOf(RegExp(r'\s//'));
          return trailing >= 0 ? l.substring(0, trailing) : l;
        })
        .join('\n');

    final files = {
      for (final f
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')))
        f.path.replaceAll(r'\', '/'): code(f.readAsStringSync()),
    };
    const layerFile = 'lib/widgets/common/carto_basemap_layer.dart';
    const urlFile = 'lib/core/map/carto_basemap.dart';
    final tileLayer = RegExp(r'\bTileLayer\(');

    test('the matchers can fire at all (positive control)', () {
      expect(files.length, greaterThan(100));
      expect(tileLayer.hasMatch(files[layerFile]!), isTrue);
      expect(files[urlFile], contains('cartocdn'));
    });

    test('no other file builds a TileLayer — a new map cannot go keyless', () {
      final offenders = files.entries
          .where((e) => e.key != layerFile && tileLayer.hasMatch(e.value))
          .map((e) => e.key)
          .toList();
      expect(offenders, isEmpty);
    });

    test('no other file names the CARTO host', () {
      final offenders = files.entries
          .where((e) => e.key != urlFile && e.value.contains('cartocdn'))
          .map((e) => e.key)
          .toList();
      expect(offenders, isEmpty);
    });

    test('both maps use the layer and its attribution', () {
      for (final screen in [
        'lib/screens/map/map_screen.dart',
        'lib/screens/provider/profile/pro_salon_profile_screen.dart',
      ]) {
        expect(files[screen], contains('const CartoBasemapLayer()'));
        expect(files[screen], contains('const CartoAttribution()'));
      }
    });
  });
}

class _MemoryCache implements MapCachingProvider {
  _MemoryCache({this.supported = true});

  final bool supported;
  final tiles = <String, CachedMapTile>{};

  @override
  bool get isSupported => supported;

  @override
  Future<CachedMapTile?> getTile(String url) async => tiles[url];

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    tiles[url] = (bytes: bytes ?? tiles[url]!.bytes, metadata: metadata);
  }
}

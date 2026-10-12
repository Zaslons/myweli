import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/config/app_config.dart';
import '../../core/map/carto_basemap.dart';

/// The CARTO light basemap — the ONE tile layer every app map uses (the
/// consumer « Carte » and the pro « Profil du salon » pin map).
/// Design: docs/design/map-basemap-key.md §5.2.
///
/// Put it first in a `FlutterMap`'s children, and [CartoAttribution] last:
///
/// ```dart
/// FlutterMap(children: [const CartoBasemapLayer(), markers, const CartoAttribution()])
/// ```
///
/// Everything it requests comes from the pure [cartoBasemapRequest]: the URL
/// keyed with [apiKey], and CARTO's restriction headers for the running
/// platform and app. The app id is read from the OS (`PackageInfo` — the
/// bundle id on iOS, the package on Android) rather than trusted to the entry
/// point. Nothing is drawn for the frame that takes; if the id cannot be read
/// (no platform — widget tests) the layer still draws, without headers, and a
/// restricted key refuses it visibly.
class CartoBasemapLayer extends StatefulWidget {
  /// Overridable for tests only — a `flutter test` cannot set a define.
  final String apiKey;

  const CartoBasemapLayer({
    super.key,
    this.apiKey = AppConfig.cartoBasemapsKey,
  });

  @override
  State<CartoBasemapLayer> createState() => _CartoBasemapLayerState();
}

/// The [CartoPlatform] a Flutter [TargetPlatform] requests as.
CartoPlatform cartoPlatformOf(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS => CartoPlatform.ios,
  TargetPlatform.android => CartoPlatform.android,
  _ => CartoPlatform.other,
};

class _CartoBasemapLayerState extends State<CartoBasemapLayer> {
  /// Built ONCE per layer. A `TileLayer` without a `tileProvider` constructs
  /// a fresh provider (and HTTP client) in its initializer on every rebuild,
  /// and only the last one is ever disposed — which is what the screens did
  /// before this widget existed.
  NetworkTileProvider? _provider;
  String? _appId;
  final CartoPlatform _platform = cartoPlatformOf(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    _resolveAppId();
  }

  Future<void> _resolveAppId() async {
    String? id;
    try {
      final name = (await PackageInfo.fromPlatform()).packageName;
      id = name.isEmpty ? null : name;
    } on Exception {
      id = null;
    }
    if (!mounted) return;
    setState(() {
      _appId = id;
      _provider = NetworkTileProvider(
        headers: _request().headers,
        cachingProvider: const CartoWatermarkRefusingCache(),
      );
    });
  }

  CartoBasemapRequest _request() => cartoBasemapRequest(
    key: widget.apiKey,
    platform: _platform,
    appId: _appId,
  );

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null) return const SizedBox.shrink();
    final request = _request();
    return TileLayer(
      urlTemplate: request.urlTemplate,
      tileProvider: provider,
      userAgentPackageName: request.userAgentPackageName,
      retinaMode: true,
    );
  }
}

/// The attribution CARTO's terms require on every basemap view.
class CartoAttribution extends StatelessWidget {
  const CartoAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return const RichAttributionWidget(
      attributions: [
        TextSourceAttribution('© OpenStreetMap contributors'),
        TextSourceAttribution('© CARTO'),
      ],
    );
  }
}

/// flutter_map's built-in tile cache, minus CARTO's watermark.
///
/// The « API KEY REQUIRED » tile comes back `200` with
/// `cache-control: max-age=2592000, immutable` (measured 2026-10-11), and the
/// built-in cache honours that. Stored, it would keep every phone that opened
/// a map while the key was unusable — not yet activated, mistyped, refused
/// for quota — showing the watermark for 30 days after the fix, under the
/// very URL the fix makes good again. So it is never stored, and an entry
/// already holding one counts as absent. Spec §2 / §5.3.
class CartoWatermarkRefusingCache implements MapCachingProvider {
  /// [inner] for tests; the app uses flutter_map's built-in singleton,
  /// resolved lazily exactly as the tile provider would resolve it.
  final MapCachingProvider? inner;

  const CartoWatermarkRefusingCache({this.inner});

  MapCachingProvider get _delegate =>
      inner ?? BuiltInMapCachingProvider.getOrCreateInstance();

  @override
  bool get isSupported => _delegate.isSupported;

  @override
  Future<CachedMapTile?> getTile(String url) async {
    final tile = await _delegate.getTile(url);
    if (tile != null && isCartoWatermarkEtag(tile.metadata.etag)) return null;
    return tile;
  }

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    if (isCartoWatermarkEtag(metadata.etag)) return;
    await _delegate.putTile(url: url, metadata: metadata, bytes: bytes);
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/config/app_config.dart';
import '../../core/map/carto_basemap.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

/// The CARTO light basemap — the ONE tile layer every app map uses (the
/// consumer « Carte », the pro « Profil du salon » pin map and the salon
/// page's location preview). `carto_basemap_layer_test.dart` holds every
/// `FlutterMap(` in `lib/` to it.
/// Design: docs/design/map-basemap-key.md §5.2.
///
/// Put it first in a `FlutterMap`'s children, and [CartoAttribution] last
/// (`CartoAttribution.sheet()` in a map box of fixed height):
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

  /// Rings of tiles loaded beyond the visible ones — flutter_map's
  /// `TileLayer.panBuffer`, whose default (1) this keeps. A map that never
  /// moves passes 0: the ring would be requests nobody can pan to
  /// (salon-location-map.md §7).
  final int panBuffer;

  const CartoBasemapLayer({
    super.key,
    this.apiKey = AppConfig.cartoBasemapsKey,
    this.panBuffer = 1,
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
      panBuffer: widget.panBuffer,
    );
  }
}

/// The credits CARTO's terms require on every basemap view — the legal text,
/// written once for both forms of [CartoAttribution]. Not translated: it is
/// the licensors' notice, not our copy.
const cartoCredits = ['© OpenStreetMap contributors', '© CARTO'];

/// The attribution CARTO's terms require on every basemap view.
///
/// Two forms, one text ([cartoCredits]), the same « i » in the corner:
///
/// * `CartoAttribution()` — flutter_map's `RichAttributionWidget`, whose
///   credits open in a popup **inside the map**. For a map with room for that
///   popup: « Carte », the whole screen.
/// * `CartoAttribution.sheet()` — the credits open in a **bottom sheet**. For a
///   map box of fixed height: the popup is a column of text, and the salon
///   page's 160dp preview could not hold it from 1.3× text up — 56px over at
///   1.3×, 220 at 2× (salon-location-map.md §2.1 « crédits »; SYSTEM.md §13.3,
///   a box holding text has no fixed height). The sheet has the full width,
///   scrolls, and wraps at any text scale.
class CartoAttribution extends StatelessWidget {
  const CartoAttribution({
    super.key,
    this.alignment = AttributionAlignment.bottomRight,
  }) : _inSheet = false;

  const CartoAttribution.sheet({super.key})
    : _inSheet = true,
      alignment = AttributionAlignment.bottomRight;

  final bool _inSheet;

  /// The popup form's corner — a map that keeps its own controls in the
  /// bottom-right (« Carte »'s « Me localiser ») puts the credits bottom-left,
  /// or the button hides the « i » the data licence requires.
  final AttributionAlignment alignment;

  /// The sheet form's « i » — its name wherever the map does not merge it into
  /// one button (the salon preview does, salon-location-map.md §2.4).
  static const sheetTooltip = 'Crédits de la carte';

  /// The sheet's title.
  static const sheetTitle = 'Données cartographiques';

  @override
  Widget build(BuildContext context) {
    if (!_inSheet) {
      return RichAttributionWidget(
        alignment: alignment,
        attributions: [for (final c in cartoCredits) TextSourceAttribution(c)],
      );
    }
    // No `SafeArea`, unlike the popup form: a fixed box sits inside a page,
    // not against the screen's edges, and an inset would only push the « i »
    // off its corner.
    return Align(
      alignment: Alignment.bottomRight,
      child: IconButton(
        tooltip: sheetTooltip,
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          builder: (_) => const _CartoCreditsSheet(),
        ),
        icon: const Icon(
          Icons.info_outline,
          size: AppTheme.iconM,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// [CartoAttribution.sheet]'s credits: a title and the notices, at the sheet's
/// full width, scrolling should 200 % text ever need it.
class _CartoCreditsSheet extends StatelessWidget {
  const _CartoCreditsSheet();

  @override
  Widget build(BuildContext context) {
    // The full width, as every sheet in the app: inside a bottom sheet the
    // scroll view's width is loose, so without this the sheet shrank to its
    // longest line and floated centred (seen on the simulator, 2026-10-12).
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: SizedBox(
          width: double.infinity,
          child: const _CartoCreditsBody(),
        ),
      ),
    );
  }
}

class _CartoCreditsBody extends StatelessWidget {
  const _CartoCreditsBody();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              CartoAttribution.sheetTitle,
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          for (final credit in cartoCredits)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacingXS),
              child: Text(
                credit,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
        ],
      ),
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

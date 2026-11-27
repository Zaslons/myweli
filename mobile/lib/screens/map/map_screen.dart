import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:myweli/widgets/common/brand_loader.dart';
import 'package:provider/provider.dart';

import '../../core/location/location_access.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/salon_id.dart';
import '../../models/provider.dart' as models;
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/common/app_rating.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/carto_basemap_layer.dart';
import '../../widgets/common/commune_picker_sheet.dart';
import '../../widgets/common/commune_pill.dart';
import '../../widgets/common/consumer_bottom_nav.dart';
import '../../widgets/common/salon_map_marker.dart';
import '../../widgets/common/screen_title.dart';
import '../../widgets/common/timed_cached_image.dart';
import '../../widgets/provider/heart_after_sign_in.dart';

class MapScreen extends StatefulWidget {
  /// `/carte?providerId=` — open centred on this salon with its sheet up
  /// (docs/design/salon-location-map.md §2.3).
  final SalonId? focusProviderId;

  const MapScreen({super.key, this.focusProviderId});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

/// The location line over the map (consumer-location.md §2.1): the ask
/// before any dialog, then what came of a tap.
enum _LocationBanner {
  ask,
  refused,
  blocked,
  restricted,
  offAndroid,
  offIos,
  failed,
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  // Abidjan-ish default center
  static const LatLng _defaultCenter = LatLng(5.336, -4.026);
  static const double _defaultZoom = 11.5;

  final MapController _mapController = MapController();

  Position? _position;
  bool _locating = false;

  /// The location line under the pill; null: nothing to say. The map never
  /// opens the system dialog by itself: it asks first, once, and the dialog
  /// follows a tap (consumer-location.md §2.1, decision 273).
  _LocationBanner? _banner;

  /// « Me localiser », where focus goes when the banner holding it goes away;
  /// and the banner's last action — the way out — when a new banner replaces
  /// it (§2.5, SYSTEM.md §13.5).
  final FocusNode _locateFocus = FocusNode(debugLabel: 'Me localiser');
  final FocusNode _bannerActionFocus = FocusNode(debugLabel: 'location banner');

  /// The way back from the Settings the MAP opened (§2.1): set by « Ouvrir les
  /// réglages », then [_leftForSettings] once the app actually left. Only that
  /// return reads again. The system dialog's own closing brings the app back
  /// to the foreground too, and must not start a second read (§2.4).
  bool _awaitingSettings = false;
  bool _leftForSettings = false;

  /// The salon `focusProviderId` resolved to. Its marker is drawn even when
  /// the list — page 1, filtered by the chosen commune — does not hold it,
  /// and the camera is its: the user's position no longer moves it on
  /// arrival (salon-location-map.md §2.3).
  models.Provider? _focused;

  late final ProviderProvider _providers;

  /// The commune the map's salons were last asked for. The map reads them
  /// again only when the shared commune actually changed
  /// (consumer-search.md §2.7): [ProviderProvider] notifies on every salon
  /// read, the map's own included.
  String? _askedCommune;

  @override
  void initState() {
    super.initState();
    _providers = Provider.of<ProviderProvider>(context, listen: false);
    _askedCommune = _providers.selectedCommune;
    _providers.addListener(_onProviders);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final providerProvider = _providers;
      // The markers, and their hearts when signed in — STARTED, not awaited
      // before the salon below (salon-location-map.md §2.3). Nothing bounds a
      // request in time (`AppConstants.apiTimeout` is declared, never read),
      // so awaiting them kept the camera on Abidjan and the sheet shut for as
      // long as the list took — even for a salon the page beneath already
      // held. Both catch their own failures; the layer redraws as they land.
      //
      // The map's OWN salons (consumer-search.md §2.8): the chosen commune,
      // up to 50. It used to reload the list the home and the salon list
      // shared — and reset the list's category doing it.
      unawaited(providerProvider.loadMapSalons());
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.user != null) {
        final favoritesProvider = Provider.of<FavoritesProvider>(
          context,
          listen: false,
        );
        unawaited(favoritesProvider.loadFavorites(authProvider.user!.id));
      }

      // Opened from a salon page or a booking: centre that salon.
      final focusId = widget.focusProviderId;
      if (focusId != null && focusId.isNotEmpty) {
        await _focusOn(providerProvider, focusId);
        if (!mounted) return;
      }

      await _onOpen();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _providers.removeListener(_onProviders);
    _locateFocus.dispose();
    _bannerActionFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_awaitingSettings) return;
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _leftForSettings = true;
      case AppLifecycleState.resumed when _leftForSettings:
        _awaitingSettings = false;
        _leftForSettings = false;
        unawaited(_backFromSettings());
      default:
        break;
    }
  }

  void _onProviders() {
    final commune = _providers.selectedCommune;
    if (commune == _askedCommune) return;
    _askedCommune = commune;
    unawaited(_providers.loadMapSalons());
  }

  Future<void> _openCommunePicker() async {
    final choice = await showCommunePicker(
      context,
      selected: _providers.selectedCommune,
    );
    if (choice == null) return;
    await _providers.setCommune(choice.commune);
  }

  /// Centre [id] and open its sheet — wherever it is: the list already in
  /// memory, the salon page beneath this one (no network at all), or one
  /// public read running alongside the list's
  /// ([ProviderProvider.providerForMap]). The list alone missed every salon
  /// outside the commune filter or past page 1, and the map then opened on
  /// Abidjan with no sheet.
  Future<void> _focusOn(ProviderProvider providers, SalonId id) async {
    final p = await providers.providerForMap(id);
    if (!mounted) return;
    final lat = p?.latitude;
    final lng = p?.longitude;
    if (p == null || lat == null || lng == null) {
      AppSnackBar.show(
        context,
        'Ce salon n’a pas pu être affiché sur la carte.',
        kind: SnackKind.error,
      );
      return;
    }
    setState(() => _focused = p);
    _mapController.move(LatLng(lat, lng), 14);
    // Open sheet after the first frame on this screen settles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openProviderSheet(p);
    });
  }

  /// Opening « Carte » (§2.1): what the phone already allows, read with no
  /// dialog. Allowed: the position, silently. Not decided and never
  /// explained on this phone: the ask banner. Anything else: nothing —
  /// « Me localiser » stays.
  Future<void> _onOpen() async {
    final access = LocationAccess.instance;
    switch (await access.status()) {
      case LocationStatus.allowed:
        await _read(ask: false, silent: true, recenter: _focused == null);
      case LocationStatus.undecided:
        final explained = await access.explained();
        if (!mounted || explained) return;
        setState(() => _banner = _LocationBanner.ask);
      case LocationStatus.blocked ||
          LocationStatus.off ||
          LocationStatus.unknown:
        break;
    }
  }

  /// The shared flow (§5) and its outcome on the map. [ask]: `false` never
  /// opens the dialog (the silent read). [silent]: a failure shows nothing.
  /// [recenter]: move the camera to the position — not when a salon was
  /// opened, whose sheet the person is reading (salon-location-map.md §2.3).
  /// [fromBanner]: the tap came from the banner, whose button may go away,
  /// so focus moves (§2.5).
  Future<void> _read({
    required bool ask,
    bool silent = false,
    bool recenter = true,
    bool fromBanner = false,
  }) async {
    if (_locating) return; // one read at a time (§2.4)
    setState(() => _locating = true);
    final outcome = await LocationAccess.instance.locate(
      accuracy: LocationAccuracy.medium,
      ask: ask,
    );
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (outcome is Located) {
        _position = outcome.position;
        _banner = null;
      } else if (!silent) {
        _banner = _bannerFor(outcome);
      }
    });
    if (outcome case Located(:final position) when recenter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPosition(position, zoom: 13.5);
      });
    }
    if (fromBanner) _refocus();
  }

  _LocationBanner? _bannerFor(LocationOutcome outcome) => switch (outcome) {
    Located() => null,
    LocationRefused() => _LocationBanner.refused,
    LocationBlocked() => _LocationBanner.blocked,
    LocationRestricted() => _LocationBanner.restricted,
    LocationOff() =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? _LocationBanner.offIos
          : _LocationBanner.offAndroid,
    LocationFailed() => _LocationBanner.failed,
  };

  /// « Ouvrir les réglages »: the app's page, or the phone's location page
  /// when location is off (Android). The map then waits for its own return.
  Future<void> _openSettings({required bool location}) async {
    _awaitingSettings = true;
    _leftForSettings = false;
    final access = LocationAccess.instance;
    final opened = location
        ? await access.openLocationSettings()
        : await access.openAppSettings();
    if (!opened) _awaitingSettings = false;
  }

  /// Back from the Settings the map opened (§2.1): what the phone allows now,
  /// with no dialog, and the banner rebuilt from it.
  Future<void> _backFromSettings() async {
    final status = await LocationAccess.instance.status();
    if (!mounted) return;
    switch (status) {
      case LocationStatus.allowed:
        await _read(ask: false, recenter: _focused == null, fromBanner: true);
        return;
      case LocationStatus.off:
        setState(
          () => _banner = defaultTargetPlatform == TargetPlatform.iOS
              ? _LocationBanner.offIos
              : _LocationBanner.offAndroid,
        );
      case LocationStatus.blocked:
        setState(() => _banner = _LocationBanner.blocked);
      case LocationStatus.undecided:
        setState(() => _banner = _LocationBanner.refused);
      case LocationStatus.unknown:
        return;
    }
    _refocus();
  }

  /// « Plus tard » and « Fermer »: the banner goes, until the next tap. Only
  /// « Plus tard » answers the ask for good (§4).
  void _dismissBanner({bool later = false}) {
    if (later) unawaited(LocationAccess.instance.markExplained());
    setState(() => _banner = null);
    _refocus();
  }

  /// The focused button went away (§2.5): to « Me localiser » when the banner
  /// is gone, to the new banner's way out when one replaced it.
  void _refocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_banner == null ? _locateFocus : _bannerActionFocus).requestFocus();
    });
  }

  void _centerOnUser() {
    final pos = _position;
    if (pos == null) return;
    _showPosition(pos, zoom: 14);
  }

  /// The camera on the position. An approximate one (over 500 m) is framed
  /// whole, circle and all, rather than zoomed into a street it cannot claim
  /// (§2.1, decision 275).
  void _showPosition(Position pos, {required double zoom}) {
    final centre = LatLng(pos.latitude, pos.longitude);
    final radius = pos.accuracy;
    if (radius <= _framedAccuracy) {
      _mapController.move(centre, zoom);
      return;
    }
    const metresPerDegree = 111320.0;
    final dLat = radius / metresPerDegree;
    final dLng =
        radius / (metresPerDegree * math.cos(pos.latitude * math.pi / 180));
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(pos.latitude - dLat, pos.longitude - dLng),
          LatLng(pos.latitude + dLat, pos.longitude + dLng),
        ),
        padding: const EdgeInsets.all(AppTheme.spacingM),
      ),
    );
  }

  /// Above this accuracy radius, in metres, the camera frames the circle.
  static const double _framedAccuracy = 500;

  void _openProviderSheet(models.Provider p) {
    final parentContext =
        context; // preserve the widget-tree context for go_router
    showModalBottomSheet<void>(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusXXL),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingM,
                AppTheme.spacingM,
                AppTheme.spacingM,
                AppTheme.spacingL,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusPill,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                        child: TimedCachedImage(
                          imageUrl: p.imageUrls.isNotEmpty
                              ? p.imageUrls.first
                              : '',
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingM),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: AppTextStyles.titleLarge.copyWith(
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AppTheme.spacingXS),
                            AppRating(
                              rating: p.rating,
                              reviewCount: p.reviewCount,
                              size: AppRatingSize.compact,
                            ),
                            const SizedBox(height: AppTheme.spacingXS),
                            Text(
                              p.city ?? p.address,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textTertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Consumer2<AuthProvider, FavoritesProvider>(
                        builder: (_, auth, favorites, _) {
                          final isFav = auth.isAuthenticated
                              ? favorites.isFavorite(p.id)
                              : false;
                          return IconButton(
                            tooltip: isFav
                                ? 'Retirer des favoris'
                                : 'Ajouter aux favoris',
                            onPressed: () async {
                              if (!auth.isAuthenticated || auth.user == null) {
                                // The sheet closes, the sign-in opens over
                                // the map, and the salon is added there; the
                                // sheet is gone, so the map screen says it
                                // (§2.8, decision 205).
                                final router = GoRouter.of(parentContext);
                                final messenger = ScaffoldMessenger.of(
                                  parentContext,
                                );
                                Navigator.of(sheetCtx).pop();
                                await heartAfterSignIn(
                                  router: router,
                                  messenger: messenger,
                                  auth: auth,
                                  favorites: favorites,
                                  salonId: p.id,
                                );
                                return;
                              }
                              final ok = await favorites.toggleFavorite(
                                auth.user!.id,
                                p.id,
                              );
                              if (sheetCtx.mounted) {
                                // A snackbar here would be pruned by the
                                // sheet's ModalBarrier (§15/§10), so this one
                                // stays an announcement — but it must not
                                // announce a success that did not happen.
                                Helpers.announce(
                                  sheetCtx,
                                  ok
                                      ? (isFav
                                            ? 'Retiré des favoris'
                                            : 'Ajouté aux favoris')
                                      : (favorites.error ??
                                            'Une erreur est survenue. Réessayez.'),
                                );
                              }
                            },
                            icon: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              color: isFav
                                  ? AppColors.favorite
                                  : AppColors.textPrimary,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetCtx).pop();
                        parentContext.push('/provider/${p.id}');
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Voir le salon'),
                    ),
                  ),
                  if (p.latitude != null && p.longitude != null) ...[
                    const SizedBox(height: AppTheme.spacingSM),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          Helpers.launchNavigation(
                            latitude: p.latitude!,
                            longitude: p.longitude!,
                            label: p.name,
                            context: parentContext,
                          );
                        },
                        icon: const Icon(Icons.directions),
                        label: const Text('Y aller'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceVariant,
                          foregroundColor: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Marker> _buildProviderMarkers(BuildContext context) {
    final providerProvider = context.watch<ProviderProvider>();
    final favoritesProvider = context.watch<FavoritesProvider>();
    final focused = _focused;
    final salons = providerProvider.mapSalons ?? const <models.Provider>[];
    final providers = [
      ...salons,
      // The centred salon, when the map's list does not hold it — another
      // commune's, or past the 50 — or its sheet closes on an empty spot.
      if (focused != null && !salons.any((p) => p.id == focused.id)) focused,
    ];

    return providers.where((p) => p.latitude != null && p.longitude != null).map((
      p,
    ) {
      final lat = p.latitude!;
      final lng = p.longitude!;
      final isFav = favoritesProvider.isFavorite(p.id);

      return Marker(
        point: LatLng(lat, lng),
        width: 48,
        height: 48,
        child: Semantics(
          button: true,
          label: p.name, // §13.4: each pin names its salon, not a bare icon
          child: GestureDetector(
            onTap: () {
              // Subtle “smooth” behavior: center the tapped salon, show details.
              _mapController.move(LatLng(lat, lng), 14);
              _openProviderSheet(p);
            },
            child: SalonMapMarker(category: p.category, isFavorite: isFav),
          ),
        ),
      );
    }).toList();
  }

  Marker? _buildUserMarker() {
    final pos = _position;
    if (pos == null) return null;
    return Marker(
      point: LatLng(pos.latitude, pos.longitude),
      width: 22,
      height: 22,
      // §2.5: the dot says what it is; it was a bare circle.
      child: Semantics(
        label: 'Votre position',
        container: true,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.info,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: AppTheme.elevation2,
          ),
        ),
      ),
    );
  }

  /// How approximate the position is (§2.1): a radius in metres, under the
  /// dot. Decoration — the dot carries the meaning and the label.
  CircleLayer? _buildAccuracyCircle() {
    final pos = _position;
    if (pos == null || pos.accuracy <= 0) return null;
    return CircleLayer(
      circles: [
        CircleMarker(
          point: LatLng(pos.latitude, pos.longitude),
          radius: pos.accuracy,
          useRadiusInMeter: true,
          color: AppColors.locationAccuracy,
        ),
      ],
    );
  }

  /// The location line (§2.1): the ask, then what came of a tap. A live
  /// region, like the map's other lines: it is what the person waits to hear.
  /// While a read runs, its actions are disabled — one read at a time.
  Widget? _locationBanner() {
    final banner = _banner;
    if (banner == null) return null;
    final idle = !_locating;
    final close = _BannerAction('Fermer', idle ? () => _dismissBanner() : null);
    final settings = _BannerAction(
      'Ouvrir les réglages',
      idle ? () => unawaited(_openSettings(location: false)) : null,
    );
    final Widget child = switch (banner) {
      _LocationBanner.ask => _MapBanner(
        icon: Icons.my_location,
        title: 'Voir les salons autour de vous ?',
        text:
            'Autorisez la localisation pour centrer la carte sur votre '
            'position.',
        actions: [
          _BannerAction(
            'Plus tard',
            idle ? () => _dismissBanner(later: true) : null,
          ),
          _BannerAction(
            'Activer',
            idle ? () => unawaited(_read(ask: true, fromBanner: true)) : null,
          ),
        ],
        lastActionFocus: _bannerActionFocus,
      ),
      _LocationBanner.refused => _MapBanner(
        icon: Icons.location_disabled,
        text:
            'Localisation refusée. Choisissez une commune en haut de la '
            'carte, ou autorisez-la.',
        actions: [
          close,
          _BannerAction(
            'Autoriser',
            idle ? () => unawaited(_read(ask: true, fromBanner: true)) : null,
          ),
        ],
        lastActionFocus: _bannerActionFocus,
      ),
      _LocationBanner.blocked => _MapBanner(
        icon: Icons.location_disabled,
        text:
            'Localisation bloquée. Autorisez-la dans les réglages du '
            'téléphone pour centrer la carte sur vous.',
        actions: [close, settings],
        lastActionFocus: _bannerActionFocus,
      ),
      _LocationBanner.restricted => _MapBanner(
        icon: Icons.location_disabled,
        text:
            'La localisation est limitée sur ce téléphone, par Temps d’écran '
            'ou un profil installé. Choisissez une commune en haut de la '
            'carte.',
        actions: [close],
        lastActionFocus: _bannerActionFocus,
      ),
      _LocationBanner.offAndroid => _MapBanner(
        icon: Icons.location_off_outlined,
        text:
            'La localisation du téléphone est désactivée. Activez-la dans '
            'les réglages, ou choisissez une commune.',
        actions: [
          close,
          _BannerAction(
            'Ouvrir les réglages',
            idle ? () => unawaited(_openSettings(location: true)) : null,
          ),
        ],
        lastActionFocus: _bannerActionFocus,
      ),
      // An app can open only its own page on iOS, which cannot turn the
      // service on: the sentence gives the path.
      _LocationBanner.offIos => _MapBanner(
        icon: Icons.location_off_outlined,
        text:
            'Le service de localisation est désactivé. Activez-le dans '
            'Réglages › Confidentialité et sécurité › Service de '
            'localisation.',
        actions: [close],
        lastActionFocus: _bannerActionFocus,
      ),
      _LocationBanner.failed => _MapBanner(
        icon: Icons.error_outline,
        text:
            'Position introuvable. Réessayez, ou choisissez une commune en '
            'haut de la carte.',
        actions: [
          close,
          _BannerAction(
            'Réessayer',
            idle ? () => unawaited(_read(ask: true, fromBanner: true)) : null,
          ),
        ],
        lastActionFocus: _bannerActionFocus,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacingS),
      child: Semantics(liveRegion: true, container: true, child: child),
    );
  }

  /// Under the pill (§2.8): the salons loading, their failure, the map
  /// empty, or more salons than shown. A live region, so a screen reader
  /// hears what the map now holds. Null: nothing to say.
  Widget? _salonsStatus(ProviderProvider provider) {
    final salons = provider.mapSalons;
    final commune = provider.mapCommune;
    final Widget child;
    if (provider.mapLoading) {
      child = const _MapLoadingPill();
    } else if (provider.mapError != null) {
      child = _MapBanner(
        icon: Icons.error_outline,
        text: 'Impossible d’afficher les salons.',
        actions: [_BannerAction('Réessayer', provider.loadMapSalons)],
      );
    } else if (salons == null) {
      return null;
    } else if (salons.isEmpty) {
      // Not over a focused salon: opened from a salon page, its pin may be
      // in another commune, and the map is then not empty.
      if (_focused != null) return null;
      child = commune != null
          ? _MapBanner(
              icon: Icons.location_off_outlined,
              text: 'Aucun salon à $commune',
              actions: [
                _BannerAction(
                  'Toutes les communes',
                  () => provider.setCommune(null),
                ),
              ],
            )
          : const _MapBanner(
              icon: Icons.location_off_outlined,
              text: 'Aucun salon sur la carte pour l’instant',
            );
    } else if (provider.mapTotal > salons.length) {
      final shown = salons.length;
      final total = provider.mapTotal;
      child = _MapBanner(
        icon: Icons.info_outline,
        text: commune != null
            ? '$shown salons sur $total à $commune affichés'
            : '$shown salons sur $total affichés — choisissez une commune',
      );
    } else {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacingS),
      // The outcome is announced — the failure, the empty commune, the 50
      // line — and not « Chargement des salons… », said on every commune
      // and every « Réessayer » before the sentence that matters.
      child: Semantics(
        liveRegion: !provider.mapLoading,
        container: true,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final providerMarkers = _buildProviderMarkers(context);
    final userMarker = _buildUserMarker();
    final accuracyCircle = _buildAccuracyCircle();

    final markers = <Marker>[...providerMarkers, ?userMarker];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const ScreenTitle('Carte')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: _defaultZoom,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              // The keyed CARTO light basemap + its required attribution
              // (docs/design/map-basemap-key.md).
              const CartoBasemapLayer(),
              ?accuracyCircle,
              MarkerLayer(markers: markers),
              // Bottom-left: « Me localiser » owns the bottom-right corner and
              // hid the « i » the data licence requires (seen on the simulator,
              // 2026-10-12).
              const CartoAttribution(
                alignment: AttributionAlignment.bottomLeft,
              ),
            ],
          ),
          // Top: the commune the map shows, its salons' state, then the
          // location line (consumer-search.md §2.8, consumer-location.md §2.1).
          Positioned(
            left: AppTheme.spacingM,
            right: AppTheme.spacingM,
            top: AppTheme.spacingM,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Consumer<ProviderProvider>(
                  builder: (context, provider, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CommunePill(
                        commune: provider.selectedCommune,
                        onTap: _openCommunePicker,
                      ),
                      ?_salonsStatus(provider),
                    ],
                  ),
                ),
                ?_locationBanner(),
              ],
            ),
          ),
          Positioned(
            right: AppTheme.spacingM,
            bottom: AppTheme.spacingM,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'center_me',
                  tooltip: 'Me localiser',
                  focusNode: _locateFocus,
                  // While a read runs it shows the loader and ignores taps
                  // (`_read` returns): disabled, it would drop the focus it
                  // holds (§2.5). Explicit, it always moves the camera.
                  onPressed: (_position != null)
                      ? _centerOnUser
                      : () => unawaited(_read(ask: true)),
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.secondary,
                  child: _locating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: BrandLoader(
                            size: AppTheme.iconS,
                            fast: true,
                            onDark: true,
                          ),
                        )
                      : const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const ConsumerBottomNav(current: ConsumerTab.carte),
    );
  }
}

/// An action on a [_MapBanner]: a verb, and what it does — `null` while it
/// cannot (a location read running).
class _BannerAction {
  const _BannerAction(this.label, this.onPressed);

  final String label;
  final VoidCallback? onPressed;
}

/// A line over the map: the `secondary` surface, `radiusLarge`, elevation 2,
/// an icon, a sentence that wraps — [title] first, in bold, when it has one —
/// and its actions under the sentence, at the end. « Toutes les communes »
/// beside « Aucun salon à Cocody » overflowed the line at 390dp; the location
/// lines carry two actions, which wrap to two lines at 200 % (§2.4).
///
/// [lastActionFocus]: the last action's focus node, where focus lands when
/// this line replaces another (consumer-location.md §2.5).
class _MapBanner extends StatelessWidget {
  const _MapBanner({
    required this.icon,
    required this.text,
    this.title,
    this.actions = const [],
    this.lastActionFocus,
  });

  final IconData icon;
  final String text;
  final String? title;
  final List<_BannerAction> actions;
  final FocusNode? lastActionFocus;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.bodySmall.copyWith(
      color: AppColors.textSecondary,
    );
    final heading = title;
    final sentence = heading == null
        ? Text(text, style: style)
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$heading ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: text),
              ],
            ),
            style: style,
          );
    final buttons = [
      for (var i = 0; i < actions.length; i++)
        TextButton(
          focusNode: i == actions.length - 1 ? lastActionFocus : null,
          onPressed: actions[i].onPressed,
          child: Text(actions[i].label),
        ),
    ];
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      color: AppColors.secondary,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary),
            const SizedBox(width: AppTheme.spacingS),
            Expanded(
              child: buttons.isEmpty
                  ? sentence
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        sentence,
                        Align(
                          alignment: Alignment.centerRight,
                          child: buttons.length == 1
                              ? buttons.single
                              : Wrap(
                                  alignment: WrapAlignment.end,
                                  children: buttons,
                                ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// « Chargement des salons… »: small, under the pill — the map itself shows
/// at once (§2.8).
class _MapLoadingPill extends StatelessWidget {
  const _MapLoadingPill();

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      color: AppColors.secondary,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingM,
          vertical: AppTheme.spacingS,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The sentence says it; the loader's own « Chargement… » would
            // be read twice.
            const ExcludeSemantics(
              child: BrandLoader(size: AppTheme.iconS, fast: true),
            ),
            const SizedBox(width: AppTheme.spacingS),
            Flexible(
              child: Text(
                'Chargement des salons…',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

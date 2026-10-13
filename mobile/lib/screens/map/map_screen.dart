import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:myweli/widgets/common/brand_loader.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/helpers.dart';
import '../../models/provider.dart' as models;
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/common/app_rating.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/carto_basemap_layer.dart';
import '../../widgets/common/consumer_bottom_nav.dart';
import '../../widgets/common/salon_map_marker.dart';
import '../../widgets/common/timed_cached_image.dart';

class MapScreen extends StatefulWidget {
  /// `/carte?providerId=` — open centred on this salon with its sheet up
  /// (docs/design/salon-location-map.md §2.3).
  final String? focusProviderId;

  const MapScreen({super.key, this.focusProviderId});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Abidjan-ish default center
  static const LatLng _defaultCenter = LatLng(5.336, -4.026);
  static const double _defaultZoom = 11.5;

  final MapController _mapController = MapController();

  Position? _position;
  bool _locating = false;
  String? _locationError;

  /// The salon `focusProviderId` resolved to. Its marker is drawn even when
  /// the list — page 1, filtered by the chosen commune — does not hold it,
  /// and the camera is its: the user's position no longer moves it on
  /// arrival (salon-location-map.md §2.3).
  models.Provider? _focused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final providerProvider = Provider.of<ProviderProvider>(
        context,
        listen: false,
      );
      // The markers, and their hearts when signed in — STARTED, not awaited
      // before the salon below (salon-location-map.md §2.3). Nothing bounds a
      // request in time (`AppConstants.apiTimeout` is declared, never read),
      // so awaiting them kept the camera on Abidjan and the sheet shut for as
      // long as the list took — even for a salon the page beneath already
      // held. Both catch their own failures; the layer redraws as they land.
      unawaited(providerProvider.loadProviders());
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

      await _initLocation(recenter: _focused == null);
    });
  }

  /// Centre [id] and open its sheet — wherever it is: the list already in
  /// memory, the salon page beneath this one (no network at all), or one
  /// public read running alongside the list's
  /// ([ProviderProvider.providerForMap]). The list alone missed every salon
  /// outside the commune filter or past page 1, and the map then opened on
  /// Abidjan with no sheet.
  Future<void> _focusOn(ProviderProvider providers, String id) async {
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

  /// Ask for the user's position and draw it. [recenter]: move the camera
  /// there when it arrives — not when a salon was centred, whose sheet the
  /// user is reading (salon-location-map.md §2.3). « Me localiser » and
  /// « Activer » call this bare, and recenter.
  Future<void> _initLocation({bool recenter = true}) async {
    setState(() {
      _locating = true;
      _locationError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _position = null;
          _locationError = 'Localisation désactivée';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _position = null;
          _locationError = 'Autorisez la localisation pour vous centrer';
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _position = pos;
      });
      if (!recenter) return;

      // Center map on the user after we have a position (clean first experience)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(LatLng(pos.latitude, pos.longitude), 13.5);
      });
    } catch (e) {
      setState(() {
        _locationError = e.toString();
      });
    } finally {
      setState(() {
        _locating = false;
      });
    }
  }

  void _centerOnUser() {
    final pos = _position;
    if (pos == null) return;
    _mapController.move(LatLng(pos.latitude, pos.longitude), 14);
  }

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
                                Navigator.of(sheetCtx).pop();
                                parentContext.go(
                                  '/login?returnTo=${Uri.encodeComponent('/carte')}',
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
    final providers = [
      ...providerProvider.providers,
      // The centred salon, when the list does not hold it — or its sheet
      // closes on an empty spot of the map.
      if (focused != null &&
          !providerProvider.providers.any((p) => p.id == focused.id))
        focused,
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
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.info,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: AppTheme.elevation2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final providerMarkers = _buildProviderMarkers(context);
    final userMarker = _buildUserMarker();

    final markers = <Marker>[...providerMarkers, ?userMarker];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Carte')),
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
              MarkerLayer(markers: markers),
              // Bottom-left: « Me localiser » owns the bottom-right corner and
              // hid the « i » the data licence requires (seen on the simulator,
              // 2026-10-12).
              const CartoAttribution(
                alignment: AttributionAlignment.bottomLeft,
              ),
            ],
          ),
          if (_locationError != null)
            Positioned(
              left: AppTheme.spacingM,
              right: AppTheme.spacingM,
              top: AppTheme.spacingM,
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                color: AppColors.secondary,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingM),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppTheme.spacingS),
                      Expanded(
                        child: Text(
                          _locationError!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _initLocation,
                        child: const Text('Activer'),
                      ),
                    ],
                  ),
                ),
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
                  onPressed: (_position != null)
                      ? _centerOnUser
                      : _initLocation,
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

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
import '../../core/utils/category_colors.dart';
import '../../core/utils/helpers.dart';
import '../../models/provider.dart' as models;
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/common/timed_cached_image.dart';

class MapScreen extends StatefulWidget {
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Load providers so we can place markers
      final providerProvider =
          Provider.of<ProviderProvider>(context, listen: false);
      await providerProvider.loadProviders();
      if (!mounted) return;

      // Load favorites if user is authenticated (for heart markers)
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.user != null) {
        final favoritesProvider =
            Provider.of<FavoritesProvider>(context, listen: false);
        await favoritesProvider.loadFavorites(authProvider.user!.id);
      }

      // If we were opened from a provider/booking, focus that provider on the map.
      final focusId = widget.focusProviderId;
      if (focusId != null && focusId.isNotEmpty) {
        final p = providerProvider.providers
            .where((x) => x.id == focusId)
            .cast<models.Provider?>()
            .firstWhere((x) => x != null, orElse: () => null);
        if (p != null && p.latitude != null && p.longitude != null) {
          final lat = p.latitude!;
          final lng = p.longitude!;
          _mapController.move(LatLng(lat, lng), 14);
          // Open sheet after the first frame on this screen settles.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _openProviderSheet(p);
          });
        }
      }

      await _initLocation();
    });
  }

  Future<void> _initLocation() async {
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

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'spa':
        return Icons.spa;
      case 'barber':
        return Icons.content_cut;
      case 'salon':
        return Icons.face_retouching_natural;
      default:
        return Icons.store_mall_directory;
    }
  }

  Color _categoryColor(String category) => categoryColor(category);

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
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXXL)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.spacingM,
                  AppTheme.spacingM, AppTheme.spacingM, AppTheme.spacingL),
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
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusPill),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                        child: TimedCachedImage(
                          imageUrl:
                              p.imageUrls.isNotEmpty ? p.imageUrls.first : '',
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
                              style: AppTextStyles.titleLarge
                                  .copyWith(color: AppColors.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AppTheme.spacingXS),
                            Row(
                              children: [
                                const Icon(Icons.star,
                                    size: AppTheme.iconXS,
                                    color: AppColors.starRating),
                                const SizedBox(width: AppTheme.spacingXS),
                                Text(
                                  p.rating.toStringAsFixed(1),
                                  style: AppTextStyles.bodySmall
                                      .copyWith(color: AppColors.textSecondary),
                                ),
                                const SizedBox(width: AppTheme.spacingS),
                                Text(
                                  '(${p.reviewCount})',
                                  style: AppTextStyles.bodySmall
                                      .copyWith(color: AppColors.textTertiary),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppTheme.spacingXS),
                            Text(
                              p.city ?? p.address,
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Consumer2<AuthProvider, FavoritesProvider>(
                        builder: (_, auth, favorites, __) {
                          final isFav = auth.isAuthenticated
                              ? favorites.isFavorite(p.id)
                              : false;
                          return IconButton(
                            onPressed: () async {
                              if (!auth.isAuthenticated || auth.user == null) {
                                Navigator.of(sheetCtx).pop();
                                parentContext.go(
                                    '/login?returnTo=${Uri.encodeComponent('/favorites')}');
                                return;
                              }
                              await favorites.toggleFavorite(
                                  auth.user!.id, p.id);
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
    final providers = providerProvider.providers;

    return providers
        .where((p) => p.latitude != null && p.longitude != null)
        .map((p) {
      final lat = p.latitude!;
      final lng = p.longitude!;
      final isFav = favoritesProvider.isFavorite(p.id);
      final icon = _categoryIcon(p.category);
      final color = _categoryColor(p.category);

      return Marker(
        point: LatLng(lat, lng),
        width: 44,
        height: 44,
        child: GestureDetector(
          onTap: () {
            // Subtle “smooth” behavior: center the tapped salon and show details.
            _mapController.move(LatLng(lat, lng), 14);
            _openProviderSheet(p);
          },
          child: _SalonMarker(
            icon: icon,
            color: color,
            isFavorite: isFav,
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

    final markers = <Marker>[
      ...providerMarkers,
      if (userMarker != null) userMarker,
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Carte'),
      ),
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
              TileLayer(
                // Clean "light" basemap (no API key).
                // Requires attribution; we show it via the AttributionWidget below.
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.sadreddine.myweli',
                retinaMode: true,
              ),
              MarkerLayer(markers: markers),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                  TextSourceAttribution('© CARTO'),
                ],
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
                      const Icon(Icons.info_outline,
                          color: AppColors.textSecondary),
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
                  onPressed:
                      (_position != null) ? _centerOnUser : _initLocation,
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.secondary,
                  child: _locating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: BrandLoader(
                              size: AppTheme.iconS, fast: true, onDark: true),
                        )
                      : const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        onTap: (index) {
          if (index == 0) context.go('/home');
          if (index == 2) context.push('/bookings');
          if (index == 3) context.push('/notifications');
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Accueil',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Carte',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Rendez-vous',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_none),
            label: 'Actu',
          ),
        ],
      ),
    );
  }
}

class _SalonMarker extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isFavorite;

  const _SalonMarker({
    required this.icon,
    required this.color,
    required this.isFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            boxShadow: AppTheme.elevation2,
          ),
          child: Center(
            child: Icon(icon, color: color, size: AppTheme.iconS),
          ),
        ),
        if (isFavorite)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.favorite,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.favorite,
                  size: AppTheme.iconXS, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../common/carto_basemap_layer.dart';
import '../common/salon_map_marker.dart';

/// Where the salon is, at a glance — the top of the salon page's « Contact »
/// card, the app's counterpart of the website's « Localisation » map
/// (docs/design/salon-location-map.md §2.1).
///
/// **A picture of a map, not a map.** It never pans, zooms or pinches: a map
/// inside a scrolling page that takes drags is a map that steals the scroll,
/// and the full map is one tap away. With no drag flag, flutter_map registers
/// no drag recogniser at all, so a vertical drag here scrolls the page.
///
/// Tapping anywhere but the attribution's « i » calls [onOpen]; where that
/// leads is the caller's decision — the consumer app has a map screen, the
/// pro « Aperçu » does not (§2.2). For a screen reader it is one button,
/// « Voir {nom} sur la carte », the website pin's own label.
class SalonLocationPreview extends StatelessWidget {
  final String salonName;
  final String category;
  final double latitude;
  final double longitude;
  final VoidCallback onOpen;

  /// The box's height. Constant chrome — no text inside, so 200 % text does
  /// not move it. A named constant at the call site and not an `AppTheme`
  /// token, by SYSTEM.md §5 « What §5 does not govern »: there is no sizing
  /// scale, and a map box's height is a layout dimension like the cover's
  /// `_coverHeight`. 160, not the website's 256 (`h-64`): this one is a
  /// preview whose real map is a tap away.
  static const double height = 160;

  /// The website's `zoom: 15` (`SalonLocationMap.tsx`) — a few streets.
  static const double zoom = 15;

  /// The `Marker` box — `MapScreen`'s, so the pin is the same size here.
  static const double _markerSize = 48;

  const SalonLocationPreview({
    super.key,
    required this.salonName,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final salon = LatLng(latitude, longitude);
    return Semantics(
      button: true,
      label: 'Voir $salonName sur la carte',
      // Not tiles, a pin and an « Attributions » button one by one: one
      // control, one name (SYSTEM.md §13.4).
      excludeSemantics: true,
      onTap: onOpen,
      child: ClipRRect(
        // The website's `rounded-lg`; inside a radiusXL card.
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        child: SizedBox(
          width: double.infinity,
          height: height,
          // flutter_map's keyboard `Focus` would be a stop with no visible
          // indicator; the address row just below is the keyboard path.
          child: ExcludeFocus(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: salon,
                initialZoom: zoom,
                // The neutral surface the tiles arrive on, and what stays
                // when they cannot (the website's `bg-surfaceVariant`).
                backgroundColor: AppColors.surfaceVariant,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
                onTap: (_, _) => onOpen(),
              ),
              children: [
                const CartoBasemapLayer(panBuffer: 0),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: salon,
                      width: _markerSize,
                      height: _markerSize,
                      child: SalonMapMarker(category: category),
                    ),
                  ],
                ),
                const CartoAttribution(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

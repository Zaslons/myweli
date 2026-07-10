import type { Provider } from '../api/providers';
import { colors } from '../../styles/tokens';

/// Pure helpers for the /recherche discovery map
/// (docs/design/web-discovery-map.md §3) — mirrors the app's `MapScreen`
/// constants + the DESIGN-STANDARDS §7 category-color mapping (the web copy
/// of `category_colors.dart`; values live in styles/tokens.ts). Unit-tested.

/// The app's Abidjan-ish default center + zoom.
export const ABIDJAN_CENTER: [number, number] = [5.336, -4.026];
export const DEFAULT_ZOOM = 12;

/// §7 canonical mapping — unknown categories fall back to primary.
export function markerColor(category: string | null | undefined): string {
  switch (category) {
    case 'spa':
      return colors.categorySpa;
    case 'barber':
      return colors.categoryBarber;
    case 'salon':
      return colors.categorySalon;
    default:
      return colors.primary;
  }
}

export type MappableProvider = Provider & {
  latitude: number;
  longitude: number;
};

/// The providers that can be placed on the map (the rest stay list-only,
/// exactly like the app).
export function withCoords(items: Provider[]): MappableProvider[] {
  return items.filter(
    (p): p is MappableProvider => p.latitude != null && p.longitude != null,
  );
}

/// Bounding box of the mappable results — null when nothing is mappable
/// (the map falls back to the Abidjan default).
export function boundsFor(
  items: MappableProvider[],
): [[number, number], [number, number]] | null {
  if (items.length === 0) return null;
  let south = items[0].latitude;
  let north = items[0].latitude;
  let west = items[0].longitude;
  let east = items[0].longitude;
  for (const p of items) {
    if (p.latitude < south) south = p.latitude;
    if (p.latitude > north) north = p.latitude;
    if (p.longitude < west) west = p.longitude;
    if (p.longitude > east) east = p.longitude;
  }
  return [
    [south, west],
    [north, east],
  ];
}

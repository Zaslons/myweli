import { describe, expect, it } from 'vitest';
import type { Provider } from '../lib/api/providers';
import {
  FALLBACK_CENTER,
  boundsFor,
  centerOf,
  markerColor,
  withCoords,
} from '../lib/discovery/map';
import { colors } from '../styles/tokens';
import { providerFixture } from './fixtures';

/// The /recherche discovery-map helpers (docs/design/web-discovery-map.md §3).

describe('markerColor', () => {
  it('maps the §7 canonical categories to their tokens', () => {
    expect(markerColor('spa')).toBe(colors.categorySpa);
    expect(markerColor('barber')).toBe(colors.categoryBarber);
    expect(markerColor('salon')).toBe(colors.categorySalon);
  });

  it('unknown/missing categories fall back to primary', () => {
    expect(markerColor('nails')).toBe(colors.primary);
    expect(markerColor(null)).toBe(colors.primary);
  });
});

describe('withCoords', () => {
  it('keeps only providers that can be placed on the map', () => {
    const noCoords: Provider = {
      ...providerFixture,
      id: 'p2',
      latitude: undefined,
      longitude: undefined,
    };
    const r = withCoords([providerFixture, noCoords]);
    expect(r.map((p) => p.id)).toEqual([providerFixture.id]);
  });
});

describe('centerOf (multi-pays MP3 — city centroids from the tree)', () => {
  it('a city centroid maps to [lng, lat]; degraded tree → the fallback', () => {
    expect(centerOf({ lat: 0.4162, lng: 9.4673 })).toEqual([9.4673, 0.4162]);
    expect(centerOf(null)).toEqual(FALLBACK_CENTER);
    expect(centerOf({ lat: null, lng: null })).toEqual(FALLBACK_CENTER);
  });
});

describe('boundsFor', () => {
  it('null when nothing is mappable (map stays on the fallback center)', () => {
    expect(boundsFor([])).toBeNull();
    expect(FALLBACK_CENTER).toEqual([-4.026, 5.336]); // Wave-0, lng/lat
  });

  it('single result → a point box; multi → the enclosing box (lng/lat)', () => {
    const a = { ...providerFixture, latitude: 5.3, longitude: -4.0 };
    const b = { ...providerFixture, id: 'p2', latitude: 5.4, longitude: -3.9 };
    expect(boundsFor(withCoords([a]))).toEqual([
      [-4.0, 5.3],
      [-4.0, 5.3],
    ]);
    expect(boundsFor(withCoords([a, b]))).toEqual([
      [-4.0, 5.3],
      [-3.9, 5.4],
    ]);
  });
});

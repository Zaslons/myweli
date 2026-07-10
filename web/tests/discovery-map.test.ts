import { describe, expect, it } from 'vitest';
import type { Provider } from '../lib/api/providers';
import {
  ABIDJAN_CENTER,
  boundsFor,
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

describe('boundsFor', () => {
  it('null when nothing is mappable (map stays on Abidjan)', () => {
    expect(boundsFor([])).toBeNull();
    expect(ABIDJAN_CENTER).toEqual([5.336, -4.026]); // the app's center
  });

  it('single result → a point box; multi → the enclosing box', () => {
    const a = { ...providerFixture, latitude: 5.3, longitude: -4.0 };
    const b = { ...providerFixture, id: 'p2', latitude: 5.4, longitude: -3.9 };
    expect(boundsFor(withCoords([a]))).toEqual([
      [5.3, -4.0],
      [5.3, -4.0],
    ]);
    expect(boundsFor(withCoords([a, b]))).toEqual([
      [5.3, -4.0],
      [5.4, -3.9],
    ]);
  });
});

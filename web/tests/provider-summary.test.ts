import { describe, expect, it } from 'vitest';
import type { Service } from '../lib/api/providers';
import {
  directionsUrl,
  minActivePrice,
  osmEmbedUrl,
} from '../lib/provider-summary';

const svc = (price: number, active = true): Service =>
  ({ id: String(price), name: 's', price, active }) as Service;

describe('provider-summary', () => {
  it('minActivePrice ignores inactive; null when none', () => {
    expect(minActivePrice([svc(15000), svc(8000), svc(5000, false)])).toBe(8000);
    expect(minActivePrice([svc(5000, false)])).toBeNull();
    expect(minActivePrice([])).toBeNull();
  });

  it('osmEmbedUrl builds a bbox + marker', () => {
    const u = osmEmbedUrl(5.35, -3.99);
    expect(u).toContain('openstreetmap.org/export/embed.html');
    expect(u).toContain('marker=5.35,-3.99');
    expect(u).toMatch(/bbox=-3\.99800,5\.34200,-3\.98200,5\.35800/);
  });

  it('directionsUrl points to Google Maps', () => {
    expect(directionsUrl(5.35, -3.99)).toBe(
      'https://www.google.com/maps/search/?api=1&query=5.35,-3.99',
    );
  });
});

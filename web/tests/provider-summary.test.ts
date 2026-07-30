import { describe, expect, it } from 'vitest';
import type { Service } from '../lib/api/providers';
import {
  directionsUrl,
  minActivePrice,
} from '../lib/provider-summary';

const svc = (price: number, active = true): Service =>
  ({ id: String(price), name: 's', price, active }) as Service;

describe('provider-summary', () => {
  it('minActivePrice ignores inactive; null when none', () => {
    expect(minActivePrice([svc(15000), svc(8000), svc(5000, false)])).toBe(8000);
    expect(minActivePrice([svc(5000, false)])).toBeNull();
    expect(minActivePrice([])).toBeNull();
  });


  it('directionsUrl points to Google Maps', () => {
    expect(directionsUrl(5.35, -3.99)).toBe(
      'https://www.google.com/maps/search/?api=1&query=5.35,-3.99',
    );
  });
});

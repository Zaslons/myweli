import type { Service } from './api/providers';

/// Small pure helpers for the provider page (booking panel + map). Unit-tested.

export function minActivePrice(services: Service[] = []): number | null {
  const active = services.filter((s) => s.active !== false);
  if (active.length === 0) return null;
  return Math.min(...active.map((s) => s.price));
}

/// OpenStreetMap embed URL (no API key) — a small bbox around the point + marker.
export function directionsUrl(lat: number, lng: number): string {
  return `https://www.google.com/maps/search/?api=1&query=${lat},${lng}`;
}

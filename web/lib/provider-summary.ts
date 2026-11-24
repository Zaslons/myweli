import type { Service } from './api/providers';

/// Small pure helpers for the provider page (booking panel + map). Unit-tested.

export function minActivePrice(services: Service[] = []): number | null {
  const active = services.filter((s) => s.active !== false);
  if (active.length === 0) return null;
  return Math.min(...active.map((s) => s.price));
}

/// Directions TO a salon (A2, appointment-detail-complete.md §2.6): the app's
/// own Google URL — on a phone it opens the Maps app; on a computer Google
/// Maps asks for a starting point. Built from two numbers, never from text.
export function directionsTo(lat: number, lng: number): string {
  return `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`;
}

/// OpenStreetMap embed URL (no API key) — a small bbox around the point + marker.
export function directionsUrl(lat: number, lng: number): string {
  return `https://www.google.com/maps/search/?api=1&query=${lat},${lng}`;
}

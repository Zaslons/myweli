/// Pure helpers for the web manual-booking dialog
/// (docs/design/web-manual-booking.md §3) — the app's
/// `ProManualBookingScreen` rules, unit-tested. Services are the pro
/// profile's (looser) shape — only id + price matter here.

/// The app's running total: sum of the selected services' MIN prices (the
/// server re-prices authoritatively on create).
export function manualBookingTotal(
  services: { id: string; price?: number | null }[],
  selectedIds: string[],
): number {
  return services
    .filter((s) => selectedIds.includes(s.id))
    .reduce((sum, s) => sum + (s.price ?? 0), 0);
}

/// Combine the dialog's date (YYYY-MM-DD) + time (HH:MM) inputs into the
/// booking ISO instant (UTC — Côte d'Ivoire is UTC+0). Null when incomplete.
export function combineDateTime(ymd: string, hm: string): string | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(ymd) || !/^\d{2}:\d{2}$/.test(hm)) {
    return null;
  }
  return `${ymd}T${hm}:00.000Z`;
}

/// The app's future-only guard (« Choisissez une date et une heure à venir »).
export function isFutureIso(iso: string, now: Date = new Date()): boolean {
  const t = Date.parse(iso);
  return Number.isFinite(t) && t > now.getTime();
}

/// The submit gate, mirroring the app: ≥1 service + a datetime + a client
/// (picked from C1 or at least named).
export function canSubmitManualBooking(input: {
  serviceIds: string[];
  dateTimeIso: string | null;
  clientNamed: boolean;
}): boolean {
  return (
    input.serviceIds.length > 0 &&
    input.dateTimeIso != null &&
    input.clientNamed
  );
}

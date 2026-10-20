/// Pure helpers for the web manual-booking dialog
/// (docs/design/web-manual-booking.md §3) — the app's
/// `ProManualBookingScreen` rules, unit-tested. Services are the pro
/// profile's (looser) shape — only id + price matter here.

import { salonWallClockToUtc } from '../time';

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
/// booking ISO instant. The picked wall-clock IS salon time (multi-pays §3),
/// built offset-aware through the seam (MP3: salonWallClockToUtc replaced
/// the old hardcoded-Z construction). Null when incomplete.
export function combineDateTime(
  ymd: string,
  hm: string,
  tz?: string,
): string | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(ymd) || !/^\d{2}:\d{2}$/.test(hm)) {
    return null;
  }
  const [h, m] = hm.split(':').map(Number);
  return salonWallClockToUtc(ymd, h * 60 + m, tz).toISOString();
}

/// The app's future-only guard (« Choisissez une date et une heure à venir »).
export function isFutureIso(iso: string, now: Date = new Date()): boolean {
  const t = Date.parse(iso);
  return Number.isFinite(t) && t > now.getTime();
}

/// The submit gate: ≥1 service + a datetime. The client is NOT a condition of
/// the button — as in the app, it is judged at submit, under its field
/// (docs/design/web-manual-booking-walk-in.md). This used to demand a name and
/// say it mirrored the app, which demands the opposite.
export function canSubmitManualBooking(input: {
  serviceIds: string[];
  dateTimeIso: string | null;
}): boolean {
  return input.serviceIds.length > 0 && input.dateTimeIso != null;
}

/// The app's client rule (`ProManualBookingScreen`): a NEW client needs a
/// number unless « Client sans numéro » is ticked; the name is optional. A
/// client picked from the base brings their own (or none).
export function newClientNeedsPhone(input: {
  picked: boolean;
  withoutNumber: boolean;
}): boolean {
  return !input.picked && !input.withoutNumber;
}

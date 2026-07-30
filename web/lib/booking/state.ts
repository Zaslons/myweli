import type { Artist, Provider, Service } from '../api/providers';
import { salonToday } from '../time';

/// Pure booking-HUB state (module online-booking, K2 —
/// docs/design/booking-capacity-web-hub.md §4). A faithful port of the app's
/// `booking_hub_screen.dart`: three order-free sections (Prestations ·
/// Spécialiste · Date et heure), the first interaction fixes the entry point,
/// and the auto-advance ordering + constraint graph adapt to it. Unit-tested;
/// BookingFlow is the only UI consumer.

export type Section = 'services' | 'artist' | 'time';
export type Phase = 'hub' | 'confirm' | 'done';

export type HubState = {
  phase: Phase;
  /// Fixed by the FIRST interaction; drives the auto-advance ordering.
  entryPoint: Section | null;
  /// The expanded card.
  activeSection: Section;
  serviceIds: string[];
  /// Hair-length bucket when the selection has variants (court/moyen/long).
  lengthVariant: string | null;
  artistId: string | null;
  /// Distinguish "not picked yet" vs "picked « Pas de préférence »".
  artistChosen: boolean;
  /// Calendar date shown in the time section (YYYY-MM-DD, defaults to today).
  date: string;
  /// The chosen start (ISO datetime), null until picked / after invalidation.
  slot: string | null;
  /// The slot came from the earliest-slot auto-pick (« Prochain créneau »).
  autoPicked: boolean;
};

/// « Today » is the SALON's calendar day (multi-pays MP3: pass the viewed
/// salon's timezone; default = Wave-0 Abidjan).
export const todayYmd = (tz?: string): string => salonToday(new Date(), tz);

export function initialHubState(
  prefill?: {
    serviceIds?: string[];
    artistId?: string | null;
  },
  tz?: string,
): HubState {
  const serviceIds = prefill?.serviceIds ?? [];
  const artistId = prefill?.artistId ?? null;
  return {
    phase: 'hub',
    entryPoint: null,
    // Rebook prefill lands directly on the date/time picker (the app rule).
    activeSection: serviceIds.length > 0 ? 'time' : 'services',
    serviceIds,
    lengthVariant: null,
    artistId,
    artistChosen: artistId != null,
    date: todayYmd(tz),
    slot: null,
    autoPicked: false,
  };
}

// ---- catalogue helpers -------------------------------------------------------

export function selectedServices(p: Provider, ids: string[]): Service[] {
  return (p.services ?? []).filter((x) => ids.includes(x.id));
}

/// Hair-length variant keys, in display order (app `booking_duration.dart`).
export const lengthVariantOrder = ['court', 'moyen', 'long'] as const;

/// The duration a service takes for the chosen hair length; falls back to the
/// service default when it declares no variant for that length.
export function serviceDurationFor(s: Service, length: string | null): number {
  const v = s.durationVariants;
  if (length && v) {
    const minutes = v[length as keyof typeof v];
    if (typeof minutes === 'number') return minutes;
  }
  return s.durationMinutes;
}

/// Whether any selected service prices/times differently by length.
export function bookingHasVariants(services: Service[]): boolean {
  return services.some(
    (s) =>
      s.durationVariants &&
      (s.durationVariants.court != null ||
        s.durationVariants.moyen != null ||
        s.durationVariants.long != null),
  );
}

/// The length buckets actually offered across the selection (union), ordered.
export function availableLengthVariants(services: Service[]): string[] {
  const present = new Set<string>();
  for (const s of services) {
    const v = s.durationVariants;
    if (!v) continue;
    if (v.court != null) present.add('court');
    if (v.moyen != null) present.add('moyen');
    if (v.long != null) present.add('long');
  }
  return lengthVariantOrder.filter((k) => present.has(k));
}

/// Prefer 'moyen', else the first available bucket, else null.
export function defaultLengthVariant(services: Service[]): string | null {
  const available = availableLengthVariants(services);
  if (available.length === 0) return null;
  return available.includes('moyen') ? 'moyen' : available[0];
}

export function lengthVariantLabel(key: string): string {
  return { court: 'Court', moyen: 'Moyen', long: 'Long' }[key] ?? key;
}

/// Total duration of the selection for the chosen length (0 when empty — the
/// caller applies the 30-min time-first default for slot fetches).
export function totalDuration(
  p: Provider,
  ids: string[],
  lengthVariant: string | null = null,
): number {
  return selectedServices(p, ids).reduce(
    (n, s) => n + serviceDurationFor(s, lengthVariant),
    0,
  );
}

/// Total price range across the selected services (min … max).
export function priceTotal(
  p: Provider,
  ids: string[],
): { min: number; max: number } {
  return selectedServices(p, ids).reduce(
    (acc, s) => ({
      min: acc.min + s.price,
      max: acc.max + (s.priceMax ?? s.price),
    }),
    { min: 0, max: 0 },
  );
}

/// Estimated deposit (preview only — the server returns the authoritative
/// amount on the created booking). Uses the min total.
export function estimatedDeposit(p: Provider, ids: string[]): number {
  if (!p.depositRequired) return 0;
  return Math.round(priceTotal(p, ids).min * (p.depositPercentage ?? 0));
}

/// The app's `_artistCanDoServices` (and the K1 engine's capability rule):
/// empty selection → capable; a selection containing an unrestricted service
/// (no `artistIds`) → capable; else the artist must be listed on every one.
export function artistCanDoServices(
  p: Provider,
  artistId: string,
  serviceIds: string[],
): boolean {
  const services = selectedServices(p, serviceIds);
  if (services.length === 0) return true;
  if (services.some((s) => (s.artistIds ?? []).length === 0)) return true;
  return services.every((s) => (s.artistIds ?? []).includes(artistId));
}

/// Keep only the services/stylist that still exist on the provider (the app's
/// `sanitizeRebookSelection`) — a rebook link never references stale data.
export function sanitizeRebookSelection(
  p: Provider,
  serviceIds: string[],
  artistId: string | null,
): { serviceIds: string[]; artistId: string | null } {
  const svcIds = new Set((p.services ?? []).map((s) => s.id));
  const artIds = new Set((p.artists ?? []).map((a: Artist) => a.id));
  return {
    serviceIds: serviceIds.filter((id) => svcIds.has(id)),
    artistId: artistId && artIds.has(artistId) ? artistId : null,
  };
}

// ---- the adaptive ordering ---------------------------------------------------

/// Port of the app's `_nextSection`: where the hub auto-advances after an
/// interaction, given what's still missing and how the user entered.
export function nextSection(s: HubState, hasArtists: boolean): Section {
  const artistSatisfied = !hasArtists || s.artistChosen;
  switch (s.entryPoint) {
    case 'services':
      if (s.serviceIds.length === 0) return 'services';
      if (hasArtists && !artistSatisfied) return 'artist';
      return 'time';
    case 'artist':
      if (hasArtists && !artistSatisfied) return 'artist';
      if (s.serviceIds.length === 0) return 'services';
      return 'time';
    case 'time':
      if (s.slot == null) return 'time';
      if (s.serviceIds.length === 0) return 'services';
      return 'artist';
    case null:
      // Default order until the user starts.
      return s.serviceIds.length > 0 ? 'artist' : 'services';
  }
}

export function advance(s: HubState, hasArtists: boolean): HubState {
  return { ...s, activeSection: nextSection(s, hasArtists) };
}

export function canConfirm(s: HubState): boolean {
  return s.serviceIds.length > 0 && s.slot != null;
}

// ---- transitions (pure; the component sequences the async slot IO) -----------

function withEntryPoint(s: HubState, ep: Section): HubState {
  return s.entryPoint == null ? { ...s, entryPoint: ep } : s;
}

/// Toggle a service; drops a now-incompatible chosen artist and keeps the
/// hair-length choice valid for the new selection. The chosen slot is KEPT —
/// the component re-validates it against the new duration (and silently
/// clears via `clearSlot` when it no longer exists).
export function toggleService(s: HubState, p: Provider, id: string): HubState {
  const next = withEntryPoint(s, 'services');
  const has = next.serviceIds.includes(id);
  const serviceIds = has
    ? next.serviceIds.filter((x) => x !== id)
    : [...next.serviceIds, id];

  let { artistId, artistChosen } = next;
  if (artistId != null && !artistCanDoServices(p, artistId, serviceIds)) {
    artistId = null;
    artistChosen = false;
  }

  const selection = selectedServices(p, serviceIds);
  let { lengthVariant } = next;
  if (!bookingHasVariants(selection)) {
    lengthVariant = null;
  } else if (
    lengthVariant == null ||
    !availableLengthVariants(selection).includes(lengthVariant)
  ) {
    lengthVariant = defaultLengthVariant(selection);
  }

  return { ...next, serviceIds, artistId, artistChosen, lengthVariant };
}

export function setVariant(s: HubState, variant: string): HubState {
  return { ...s, lengthVariant: variant };
}

/// Pick a stylist (or null = « Pas de préférence »). Ignored when the stylist
/// can't perform the current selection (the row is disabled in the UI too).
export function chooseArtist(
  s: HubState,
  p: Provider,
  artistId: string | null,
): HubState {
  if (artistId != null && !artistCanDoServices(p, artistId, s.serviceIds)) {
    return s;
  }
  return { ...withEntryPoint(s, 'artist'), artistId, artistChosen: true };
}

export function setDate(s: HubState, date: string): HubState {
  return { ...withEntryPoint(s, 'time'), date };
}

export function pickSlot(s: HubState, slot: string): HubState {
  return { ...withEntryPoint(s, 'time'), slot, autoPicked: false };
}

/// The artist-first earliest-slot auto-pick: sets the slot AND moves the
/// calendar to its day, flagged for the « Prochain créneau » hint.
export function autoPickSlot(s: HubState, slot: string): HubState {
  return { ...s, slot, date: slot.slice(0, 10), autoPicked: true };
}

/// Silent invalidation: the chosen time no longer fits the selection.
export function clearSlot(s: HubState): HubState {
  return { ...s, slot: null, autoPicked: false };
}

export function openSection(s: HubState, section: Section): HubState {
  return { ...s, activeSection: section };
}

export function goPhase(s: HubState, phase: Phase): HubState {
  return { ...s, phase };
}

/// Whether the component should run the earliest-slot auto-pick after this
/// mutation (the app's artist-first rule: entry = artist, a stylist decision
/// made, services selected, no time yet).
export function shouldAutoPickEarliest(s: HubState): boolean {
  return (
    s.entryPoint === 'artist' &&
    s.artistChosen &&
    s.serviceIds.length > 0 &&
    s.slot == null
  );
}

/// Duration for slot fetches: the selection's total, or the app's 30-min
/// time-first default when nothing is selected yet.
export function slotFetchDuration(p: Provider, s: HubState): number {
  return s.serviceIds.length > 0
    ? totalDuration(p, s.serviceIds, s.lengthVariant)
    : 30;
}

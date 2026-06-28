import type { Provider, Service } from '../api/providers';

/// Pure booking-funnel state (service → staff → slot → confirm → done).
/// Unit-tested; the UI (BookingFlow) is the only consumer.

export type Step = 'services' | 'staff' | 'slot' | 'confirm' | 'done';

export type BookingState = {
  step: Step;
  serviceIds: string[];
  artistId: string | null;
  date: string | null; // YYYY-MM-DD
  slot: string | null; // ISO datetime
};

export const initialState: BookingState = {
  step: 'services',
  serviceIds: [],
  artistId: null,
  date: null,
  slot: null,
};

export type Action =
  | { type: 'toggleService'; id: string }
  | { type: 'setArtist'; id: string | null }
  | { type: 'setDate'; date: string | null }
  | { type: 'setSlot'; slot: string | null }
  | { type: 'go'; step: Step };

export function reducer(s: BookingState, a: Action): BookingState {
  switch (a.type) {
    case 'toggleService': {
      const has = s.serviceIds.includes(a.id);
      return {
        ...s,
        serviceIds: has
          ? s.serviceIds.filter((x) => x !== a.id)
          : [...s.serviceIds, a.id],
        // selection change invalidates the chosen slot (duration changed)
        slot: null,
      };
    }
    case 'setArtist':
      return { ...s, artistId: a.id };
    case 'setDate':
      return { ...s, date: a.date, slot: null };
    case 'setSlot':
      return { ...s, slot: a.slot };
    case 'go':
      return { ...s, step: a.step };
  }
}

export function selectedServices(p: Provider, ids: string[]): Service[] {
  return (p.services ?? []).filter((x) => ids.includes(x.id));
}

export function totalDuration(p: Provider, ids: string[]): number {
  return selectedServices(p, ids).reduce((n, s) => n + s.durationMinutes, 0);
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

/// Estimated deposit (preview only — the server returns the authoritative amount
/// on the created booking). Uses the min total.
export function estimatedDeposit(p: Provider, ids: string[]): number {
  if (!p.depositRequired) return 0;
  return Math.round(priceTotal(p, ids).min * (p.depositPercentage ?? 0));
}

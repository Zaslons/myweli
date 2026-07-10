import { describe, expect, it } from 'vitest';
import type { Provider } from '../lib/api/providers';
import {
  advance,
  artistCanDoServices,
  autoPickSlot,
  availableLengthVariants,
  bookingHasVariants,
  canConfirm,
  chooseArtist,
  clearSlot,
  defaultLengthVariant,
  estimatedDeposit,
  initialHubState,
  nextSection,
  pickSlot,
  priceTotal,
  sanitizeRebookSelection,
  selectedServices,
  setDate,
  shouldAutoPickEarliest,
  slotFetchDuration,
  toggleService,
  totalDuration,
} from '../lib/booking/state';
import { providerFixture } from './fixtures';

/// The K2 hub machine (docs/design/booking-capacity-web-hub.md §4) — the
/// app's order-free flow: entry-point orderings, the constraint graph,
/// length variants, rebook sanitize.

const salon: Provider = {
  ...providerFixture,
  services: [
    {
      id: 's1',
      name: 'Tresses',
      description: '',
      price: 15000,
      priceMax: 25000,
      durationMinutes: 120,
      durationVariants: { court: 90, moyen: 120, long: 180 },
      providerId: 'p1',
      active: true,
    },
    {
      id: 's2',
      name: 'Soin visage',
      description: '',
      price: 5000,
      durationMinutes: 30,
      artistIds: ['a1'], // restricted to Awa
      providerId: 'p1',
      active: true,
    },
  ],
  artists: [
    { id: 'a1', name: 'Awa', providerId: 'p1' },
    { id: 'a2', name: 'Binta', providerId: 'p1' },
  ],
};

describe('entry-point orderings (nextSection)', () => {
  it('services-first: services → artist → time', () => {
    let s = initialHubState();
    s = toggleService(s, salon, 's1');
    expect(s.entryPoint).toBe('services');
    expect(nextSection(s, true)).toBe('artist');
    s = chooseArtist(s, salon, null);
    expect(nextSection(s, true)).toBe('time');
  });

  it('artist-first: artist → services → time', () => {
    let s = initialHubState();
    s = chooseArtist(s, salon, 'a1');
    expect(s.entryPoint).toBe('artist');
    expect(nextSection(s, true)).toBe('services');
    s = toggleService(s, salon, 's1');
    expect(s.entryPoint).toBe('artist'); // fixed by the FIRST interaction
    expect(nextSection(s, true)).toBe('time');
  });

  it('time-first: time → services → artist', () => {
    let s = initialHubState();
    s = pickSlot(s, '2026-12-01T09:00:00.000Z');
    expect(s.entryPoint).toBe('time');
    expect(nextSection(s, true)).toBe('services');
    s = toggleService(s, salon, 's1');
    expect(nextSection(s, true)).toBe('artist');
  });

  it('no artists in the salon → the artist stop is skipped', () => {
    let s = initialHubState();
    s = toggleService(s, salon, 's1');
    expect(nextSection(s, false)).toBe('time');
  });

  it('advance() moves the active section along the ordering', () => {
    let s = toggleService(initialHubState(), salon, 's1');
    s = advance(s, true);
    expect(s.activeSection).toBe('artist');
  });
});

describe('constraint graph', () => {
  it('capability: restricted selection → only listed artists can do it', () => {
    expect(artistCanDoServices(salon, 'a1', ['s2'])).toBe(true);
    expect(artistCanDoServices(salon, 'a2', ['s2'])).toBe(false);
    // A selection containing an unrestricted service is open to all.
    expect(artistCanDoServices(salon, 'a2', ['s1', 's2'])).toBe(true);
    expect(artistCanDoServices(salon, 'a2', [])).toBe(true);
  });

  it('toggling to an incompatible selection drops the chosen artist', () => {
    let s = chooseArtist(initialHubState(), salon, 'a2');
    expect(s.artistChosen).toBe(true);
    s = toggleService(s, salon, 's2'); // Binta can't do the soin
    expect(s.artistId).toBeNull();
    expect(s.artistChosen).toBe(false); // force a re-pick
  });

  it('choosing an incompatible artist is a no-op', () => {
    const s = toggleService(initialHubState(), salon, 's2');
    expect(chooseArtist(s, salon, 'a2')).toBe(s);
  });

  it('the chosen slot is KEPT on selection change (component re-validates)', () => {
    let s = pickSlot(initialHubState(), '2026-12-01T09:00:00.000Z');
    s = toggleService(s, salon, 's1');
    expect(s.slot).toBe('2026-12-01T09:00:00.000Z');
    expect(clearSlot(s).slot).toBeNull(); // the silent invalidation path
  });

  it('artist-first + services + no time → earliest auto-pick fires', () => {
    let s = chooseArtist(initialHubState(), salon, 'a1');
    expect(shouldAutoPickEarliest(s)).toBe(false); // no services yet
    s = toggleService(s, salon, 's1');
    expect(shouldAutoPickEarliest(s)).toBe(true);
    s = autoPickSlot(s, '2026-12-03T10:30:00.000Z');
    expect(s.slot).toBe('2026-12-03T10:30:00.000Z');
    expect(s.date).toBe('2026-12-03'); // calendar follows the pick
    expect(s.autoPicked).toBe(true);
    expect(shouldAutoPickEarliest(s)).toBe(false);
  });

  it('services-first entry never auto-picks', () => {
    let s = toggleService(initialHubState(), salon, 's1');
    s = chooseArtist(s, salon, 'a1');
    expect(shouldAutoPickEarliest(s)).toBe(false);
  });
});

describe('length variants', () => {
  it('selection with variants gets the default (moyen)', () => {
    const s = toggleService(initialHubState(), salon, 's1');
    expect(s.lengthVariant).toBe('moyen');
    expect(bookingHasVariants(selectedServices(salon, s.serviceIds))).toBe(true);
    expect(availableLengthVariants(selectedServices(salon, s.serviceIds)))
      .toEqual(['court', 'moyen', 'long']);
  });

  it('variant drives the total duration; non-variant services keep defaults', () => {
    expect(totalDuration(salon, ['s1'], 'court')).toBe(90);
    expect(totalDuration(salon, ['s1'], 'long')).toBe(180);
    expect(totalDuration(salon, ['s1', 's2'], 'long')).toBe(180 + 30);
    expect(totalDuration(salon, ['s2'], 'long')).toBe(30);
  });

  it('deselecting the variant services clears the variant', () => {
    let s = toggleService(initialHubState(), salon, 's1');
    s = toggleService(s, salon, 's1');
    expect(s.lengthVariant).toBeNull();
    expect(defaultLengthVariant([])).toBeNull();
  });

  it('slot fetches use the 30-min time-first default before services', () => {
    const s = initialHubState();
    expect(slotFetchDuration(salon, s)).toBe(30);
    expect(slotFetchDuration(salon, toggleService(s, salon, 's1'))).toBe(120);
  });
});

describe('confirm gate + totals', () => {
  it('needs services AND a time; the stylist stays optional', () => {
    let s = toggleService(initialHubState(), salon, 's1');
    expect(canConfirm(s)).toBe(false);
    s = pickSlot(s, '2026-12-01T09:00:00.000Z');
    expect(canConfirm(s)).toBe(true);
    expect(s.artistChosen).toBe(false);
  });

  it('price range + estimated deposit unchanged from the wizard', () => {
    expect(priceTotal(salon, ['s1'])).toEqual({ min: 15000, max: 25000 });
    expect(estimatedDeposit(salon, ['s1'])).toBe(0); // depositRequired: false
  });
});

describe('rebook prefill', () => {
  it('sanitizes stale ids against the live catalogue', () => {
    const clean = sanitizeRebookSelection(salon, ['s1', 'gone'], 'nobody');
    expect(clean).toEqual({ serviceIds: ['s1'], artistId: null });
  });

  it('prefilled state lands on the time section, artist chosen', () => {
    const s = initialHubState({ serviceIds: ['s1'], artistId: 'a1' });
    expect(s.activeSection).toBe('time');
    expect(s.artistChosen).toBe(true);
    expect(s.entryPoint).toBeNull(); // orderings stay default until a real pick
  });

  it('setDate keeps the chosen slot for re-validation semantics', () => {
    let s = pickSlot(initialHubState(), '2026-12-01T09:00:00.000Z');
    s = setDate(s, '2026-12-02');
    expect(s.date).toBe('2026-12-02');
    expect(s.slot).toBe('2026-12-01T09:00:00.000Z');
  });
});

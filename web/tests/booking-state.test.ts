import { describe, expect, it } from 'vitest';
import {
  estimatedDeposit,
  initialState,
  priceTotal,
  reducer,
  totalDuration,
} from '../lib/booking/state';
import { providerFixture } from './fixtures';

describe('booking state', () => {
  it('toggles services and clears the slot on change', () => {
    let s = reducer(initialState, { type: 'setSlot', slot: 'x' });
    s = reducer(s, { type: 'toggleService', id: 's1' });
    expect(s.serviceIds).toEqual(['s1']);
    expect(s.slot).toBeNull(); // selection change invalidates the slot
    s = reducer(s, { type: 'toggleService', id: 's1' });
    expect(s.serviceIds).toEqual([]);
  });

  it('setDate clears the slot; go moves steps', () => {
    let s = reducer(initialState, { type: 'setSlot', slot: 'x' });
    s = reducer(s, { type: 'setDate', date: '2026-12-01' });
    expect(s.date).toBe('2026-12-01');
    expect(s.slot).toBeNull();
    s = reducer(s, { type: 'go', step: 'confirm' });
    expect(s.step).toBe('confirm');
  });

  it('computes total duration, price range and estimated deposit', () => {
    const ids = ['s1'];
    expect(totalDuration(providerFixture, ids)).toBe(120);
    expect(priceTotal(providerFixture, ids)).toEqual({ min: 15000, max: 25000 });
    // fixture is depositRequired:false → 0
    expect(estimatedDeposit(providerFixture, ids)).toBe(0);
  });
});

import { describe, expect, it } from 'vitest';
import { actionsFor } from '../lib/pro/lifecycle';

describe('pro lifecycle actionsFor (mirrors the app)', () => {
  it('pending → Accepter / Refuser', () => {
    expect(actionsFor('pending').map((a) => a.action)).toEqual([
      'accept',
      'reject',
    ]);
  });

  it('confirmed → terminé / absent (absent needs confirmation)', () => {
    const a = actionsFor('confirmed');
    expect(a.map((x) => x.action)).toEqual(['complete', 'no-show']);
    expect(a.find((x) => x.action === 'no-show')?.confirm).toBeTruthy();
    expect(a.find((x) => x.action === 'complete')?.confirm).toBeUndefined();
  });

  it('terminal statuses → no actions', () => {
    for (const s of ['completed', 'cancelled', 'noShow']) {
      expect(actionsFor(s)).toEqual([]);
    }
  });
});

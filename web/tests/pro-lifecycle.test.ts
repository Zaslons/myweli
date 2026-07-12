import { describe, expect, it } from 'vitest';
import { actionsFor, actionsForMembership } from '../lib/pro/lifecycle';
import type { Membership } from '../lib/pro/team';

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

/// Team access R5b — the role-shaped set (mirrors the server's T40 rule).
describe('actionsForMembership', () => {
  const staff: Membership = {
    role: 'staff',
    capabilities: ['journal.manage.own', 'journal.view.own'],
    artistId: 'a1',
    artistName: 'Awa',
  };
  const manager: Membership = {
    role: 'manager',
    capabilities: [
      'journal.manage.all',
      'journal.manage.own',
      'journal.view.all',
      'journal.view.own',
    ],
  };

  it('staff: pending → NONE (accept/reject are whole-journal acts)', () => {
    expect(actionsForMembership('pending', staff)).toEqual([]);
  });

  it('staff: confirmed → Terminé / Absent only', () => {
    expect(
      actionsForMembership('confirmed', staff).map((a) => a.action),
    ).toEqual(['complete', 'no-show']);
  });

  it('manager (journal.manage.all) → the full set', () => {
    expect(
      actionsForMembership('pending', manager).map((a) => a.action),
    ).toEqual(['accept', 'reject']);
  });

  it('LEGACY null membership → the full set (owner-shaped fallback)', () => {
    expect(actionsForMembership('pending', null).map((a) => a.action)).toEqual(
      ['accept', 'reject'],
    );
  });

  it('no journal capability at all → none', () => {
    expect(
      actionsForMembership('confirmed', { role: 'staff', capabilities: [] }),
    ).toEqual([]);
  });
});

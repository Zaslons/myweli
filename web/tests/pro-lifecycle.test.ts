import { describe, expect, it } from 'vitest';
import {
  NO_SHOW_CONFIRM,
  actionsFor,
  actionsForMembership,
  hasStarted,
  noShowConfirmLines,
} from '../lib/pro/lifecycle';
import type { Membership } from '../lib/pro/team';

const STARTED = { started: true };
const NOT_YET = { started: false };

describe('pro lifecycle actionsFor (mirrors the app)', () => {
  it('pending → Accepter / Refuser', () => {
    expect(actionsFor('pending', STARTED).map((a) => a.action)).toEqual([
      'accept',
      'reject',
    ]);
  });

  it('confirmed, once started → terminé / absent (absent needs confirmation)', () => {
    const a = actionsFor('confirmed', STARTED);
    expect(a.map((x) => x.action)).toEqual(['complete', 'no-show']);
    expect(a.find((x) => x.action === 'no-show')?.confirm).toBeTruthy();
    expect(a.find((x) => x.action === 'complete')?.confirm).toBeFalsy();
  });

  /// docs/design/web-pro-journal-panel-deposit.md §2.2 — the app's detail
  /// screen offers « Marquer comme absent » only once the start is past
  /// (`pro_appointment_detail_screen.dart:351`). The server takes a no-show on
  /// a future booking (`pro_appointment_service.dart:112-119`), and it is
  /// terminal: one stray click counted an absence against the client.
  it('confirmed, not started yet → terminé only (no absent before the start)', () => {
    expect(actionsFor('confirmed', NOT_YET).map((a) => a.action)).toEqual([
      'complete',
    ]);
  });

  it('terminal statuses → no actions', () => {
    for (const s of ['completed', 'cancelled', 'noShow']) {
      expect(actionsFor(s, STARTED)).toEqual([]);
    }
  });
});

describe('hasStarted — two instants, no timezone', () => {
  const now = new Date('2026-10-19T10:00:00.000Z');

  it('a start in the past, or exactly now, has started', () => {
    expect(hasStarted('2026-10-19T09:59:00.000Z', now)).toBe(true);
    expect(hasStarted('2026-10-19T10:00:00.000Z', now)).toBe(true);
  });

  it('a start in the future has not', () => {
    expect(hasStarted('2026-10-19T10:01:00.000Z', now)).toBe(false);
  });

  it('an offset date is the same instant (no salon-clock arithmetic)', () => {
    // 11:00 at UTC+1 is 10:00 UTC — started, at the very minute.
    expect(hasStarted('2026-10-19T11:00:00.000+01:00', now)).toBe(true);
  });

  it('an unreadable date has not started — never offer the irreversible act', () => {
    expect(hasStarted('', now)).toBe(false);
    expect(hasStarted('not a date', now)).toBe(false);
  });
});

/// The confirmation, the app's dialog word for word (§3 T10–T13), with the
/// deposit sentence only when there is a deposit.
describe('the no-show confirmation', () => {
  it('says the app’s words', () => {
    expect(NO_SHOW_CONFIRM.title).toBe('Client absent ?');
    expect(NO_SHOW_CONFIRM.confirm).toBe('Marquer absent');
  });

  it('without a deposit: one sentence', () => {
    expect(noShowConfirmLines(0)).toEqual(['Le client ne s’est pas présenté.']);
    expect(noShowConfirmLines(undefined)).toEqual([
      'Le client ne s’est pas présenté.',
    ]);
  });

  it('with a deposit: the salon keeps it, per its own policy', () => {
    expect(noShowConfirmLines(5000)).toEqual([
      'Le client ne s’est pas présenté.',
      'L’acompte est conservé selon votre politique d’annulation.',
    ]);
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
    expect(actionsForMembership('pending', staff, STARTED)).toEqual([]);
  });

  it('staff: confirmed → Terminé / Absent only', () => {
    expect(
      actionsForMembership('confirmed', staff, STARTED).map((a) => a.action),
    ).toEqual(['complete', 'no-show']);
  });

  it('staff: confirmed, not started → Terminé only', () => {
    expect(
      actionsForMembership('confirmed', staff, NOT_YET).map((a) => a.action),
    ).toEqual(['complete']);
  });

  it('manager (journal.manage.all) → the full set', () => {
    expect(
      actionsForMembership('pending', manager, STARTED).map((a) => a.action),
    ).toEqual(['accept', 'reject']);
  });

  it('LEGACY null membership → the full set (owner-shaped fallback)', () => {
    expect(
      actionsForMembership('pending', null, STARTED).map((a) => a.action),
    ).toEqual(['accept', 'reject']);
  });

  it('no journal capability at all → none', () => {
    expect(
      actionsForMembership(
        'confirmed',
        { role: 'staff', capabilities: [] },
        STARTED,
      ),
    ).toEqual([]);
  });
});

import { describe, expect, it } from 'vitest';
import {
  type Appointment,
  bookingsForTab,
  canCancel,
  canReschedule,
  clientStatusLabel,
  clientStatusTone,
  clientTab,
  groupByMonth,
  isUpcoming,
  statusLabelFr,
  visitSummary,
} from '../lib/account/appointments';

/// docs/design/web-account-bookings-truth.md §2.1–§2.4 and §8.
///
/// **Every test passes `now`.** `mk()` dates its bookings 2026-12-01: left on
/// a default clock, a pending one would move to « Passés » on that day, and
/// this suite would go red on a date rather than on a defect.
const NOW = new Date('2026-11-23T12:00:00.000Z');
const at = (minutesFromNow: number) =>
  new Date(NOW.getTime() + minutesFromNow * 60_000).toISOString();

const mk = (status: string, appointmentDate = '2026-12-01T09:00:00.000Z'): Appointment => ({
  id: `${status}@${appointmentDate}`,
  status,
  appointmentDate,
  providerId: 'p1',
});

describe('clientTab — the app’s table (§2.1)', () => {
  it('reads every spelling of an absence as one: « Passés », « Absent », error', () => {
    for (const s of ['noShow', 'no_show', 'NO_SHOW', 'no-show']) {
      for (const minutes of [-60, 60]) {
        const a = mk(s, at(minutes));
        expect(clientTab(a, NOW), `${s} ${minutes}`).toBe('past');
        expect(clientStatusLabel(a, NOW), s).toBe('Absent');
        expect(clientStatusTone(a, NOW), s).toBe('error');
      }
    }
  });

  it('places an unknown status by its date, with its raw label, never hidden', () => {
    expect(clientTab(mk('onHold', at(60)), NOW)).toBe('upcoming');
    expect(clientTab(mk('onHold', at(-60)), NOW)).toBe('past');
    expect(clientStatusLabel(mk('onHold', at(60)), NOW)).toBe('onHold');
    expect(clientStatusTone(mk('onHold', at(60)), NOW)).toBe('neutral');
    // Every booking lands in exactly one tab.
    const items = [mk('onHold', at(60)), mk('onHold', at(-60))];
    const listed = (['upcoming', 'past', 'cancelled'] as const).flatMap((t) =>
      bookingsForTab(items, t, NOW),
    );
    expect(listed).toHaveLength(2);
  });

  it('counts exactly now as past, and one minute ahead as upcoming', () => {
    expect(clientTab(mk('pending', at(0)), NOW)).toBe('past');
    expect(clientStatusLabel(mk('pending', at(0)), NOW)).toBe('Non confirmé');
    expect(clientTab(mk('confirmed', at(0)), NOW)).toBe('past');
    expect(clientTab(mk('pending', at(1)), NOW)).toBe('upcoming');
  });

  it('never says « Terminé » for a booking the salon did not close', () => {
    for (const s of ['pending', 'confirmed']) {
      expect(clientStatusLabel(mk(s, at(-60)), NOW)).not.toBe('Terminé');
    }
  });

  it('leaves the shared vocabulary alone: the Espace pro keeps « En attente »', () => {
    // « Non confirmé » lives beside `clientTab`, not in STATUS_FR.
    expect(statusLabelFr('pending')).toBe('En attente');
    expect(statusLabelFr('confirmed')).toBe('Confirmé');
    expect(statusLabelFr('noShow')).toBe('Absent');
  });
});

describe('bookingsForTab — each tab in the app’s order (§2.2)', () => {
  const soon = mk('confirmed', at(60));
  const later = mk('pending', at(60 * 24 * 7));
  const yesterday = mk('pending', at(-60 * 24));
  const lastMonth = mk('completed', at(-60 * 24 * 30));
  const absent = mk('noShow', at(-60 * 24 * 3));
  const cancelledOld = mk('cancelled', at(-60 * 24 * 10));
  const cancelledNew = mk('cancelled', at(60 * 24 * 2));
  // The server's order: newest first.
  const server = [later, cancelledNew, soon, yesterday, absent, cancelledOld, lastMonth];

  it('« À venir »: soonest first — it opened on the farthest', () => {
    expect(bookingsForTab(server, 'upcoming', NOW)).toEqual([soon, later]);
  });

  it('« Passés »: newest first, with the no-show and the unconfirmed', () => {
    expect(bookingsForTab(server, 'past', NOW)).toEqual([yesterday, absent, lastMonth]);
  });

  it('« Annulés »: newest first, cancelled only', () => {
    expect(bookingsForTab(server, 'cancelled', NOW)).toEqual([cancelledNew, cancelledOld]);
  });

  it('keeps the server’s order for two bookings at the same time', () => {
    const a = { ...mk('confirmed', at(60)), id: 'first' };
    const b = { ...mk('pending', at(60)), id: 'second' };
    expect(bookingsForTab([a, b], 'upcoming', NOW).map((x) => x.id)).toEqual([
      'first',
      'second',
    ]);
    expect(bookingsForTab([b, a], 'upcoming', NOW).map((x) => x.id)).toEqual([
      'second',
      'first',
    ]);
  });
});

describe('groupByMonth — months in the salon’s zone (§2.4)', () => {
  it('files 23:30 UTC on 31 October under « novembre » at a salon in Libreville', () => {
    const instant = '2026-10-31T23:30:00.000Z';
    const libreville = { ...mk('completed', instant), providerTimezone: 'Africa/Libreville' };
    const abidjan = { ...mk('completed', instant), id: 'abj' };
    const [lv] = groupByMonth([libreville]);
    expect(lv.key).toBe('2026-11');
    expect(lv.label).toBe('novembre 2026');
    // The control: the same instant in Abidjan (UTC+0) is still October, so
    // the zone — not the instant — decided.
    const [ab] = groupByMonth([abidjan]);
    expect(ab.key).toBe('2026-10');
    expect(ab.label).toBe('octobre 2026');
  });

  it('orders months newest first and bookings newest first inside each', () => {
    const n1 = mk('completed', '2026-11-02T09:00:00.000Z');
    const n2 = mk('pending', '2026-11-20T09:00:00.000Z');
    const o1 = mk('noShow', '2026-10-15T09:00:00.000Z');
    const groups = groupByMonth([o1, n1, n2]);
    expect(groups.map((g) => g.key)).toEqual(['2026-11', '2026-10']);
    expect(groups[0].items).toEqual([n2, n1]);
    expect(groups[1].items).toEqual([o1]);
  });
});

describe('visitSummary — « Terminé » only (§2.4, decision 167)', () => {
  it('counts and sums the completed visits only', () => {
    const items = [
      { ...mk('completed', at(-60)), totalPrice: 15_000 },
      { ...mk('completed', at(-120)), totalPrice: 10_000 },
      { ...mk('pending', at(-60)), totalPrice: 99_000 },
      { ...mk('confirmed', at(-60)), totalPrice: 99_000 },
      { ...mk('noShow', at(-60)), totalPrice: 99_000 },
    ];
    expect(visitSummary(items)).toEqual({ count: 2, total: 25_000, currency: undefined });
  });

  it('is null when nothing is « Terminé », rather than « 0 visite »', () => {
    expect(visitSummary([mk('pending', at(-60)), mk('noShow', at(-60))])).toBeNull();
    expect(visitSummary([])).toBeNull();
  });

  it('reads the NEWEST visit’s currency, then its salon’s', () => {
    const old = { ...mk('completed', at(-600)), totalPrice: 1, currency: 'XOF' };
    const newest = {
      ...mk('completed', at(-60)),
      totalPrice: 1,
      currency: null,
      providerCurrency: 'XAF',
    };
    expect(visitSummary([old, newest])?.currency).toBe('XAF');
    expect(visitSummary([newest, old])?.currency).toBe('XAF');
  });
});

describe('isUpcoming answers exactly as before (§2.1)', () => {
  // The rule before A1w, restated as the oracle.
  const before = (a: Appointment) =>
    (a.status === 'pending' || a.status === 'confirmed') &&
    Date.parse(a.appointmentDate) > NOW.getTime();

  it('for every status, before and after now — an unknown status included', () => {
    const statuses = ['pending', 'confirmed', 'completed', 'cancelled', 'noShow', 'no_show', 'onHold', 'PENDING'];
    for (const s of statuses) {
      for (const minutes of [-60, 0, 1, 60]) {
        const a = mk(s, at(minutes));
        expect(isUpcoming(a, NOW), `${s} ${minutes}`).toBe(before(a));
      }
    }
    // The case the status check exists for: `clientTab` files an unknown
    // future status under « À venir », but it never gets « Reporter ».
    expect(clientTab(mk('onHold', at(60)), NOW)).toBe('upcoming');
    expect(isUpcoming(mk('onHold', at(60)), NOW)).toBe(false);
  });

  it('canReschedule: pending/confirmed AND future only (parity 1.1)', () => {
    expect(canReschedule(mk('confirmed', at(60)), NOW)).toBe(true);
    expect(canReschedule(mk('pending', at(60)), NOW)).toBe(true);
    expect(canReschedule(mk('completed', at(60)), NOW)).toBe(false);
    expect(canReschedule(mk('confirmed', at(-60)), NOW)).toBe(false);
  });
});

describe('canCancel (unchanged)', () => {
  it('allows cancel only for pending/confirmed, at any time', () => {
    expect(canCancel(mk('pending'))).toBe(true);
    expect(canCancel(mk('confirmed', at(-60)))).toBe(true);
    expect(canCancel(mk('completed'))).toBe(false);
    expect(canCancel(mk('cancelled'))).toBe(false);
    expect(canCancel(mk('noShow'))).toBe(false);
  });
});

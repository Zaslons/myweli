import { describe, expect, it } from 'vitest';
import {
  canSubmitManualBooking,
  combineDateTime,
  isFutureIso,
  manualBookingTotal,
  newClientNeedsPhone,
} from '../lib/pro/manual-booking';

/// Web manual booking (docs/design/web-manual-booking.md §3) — the app's
/// ProManualBookingScreen rules as pure helpers.

const services = [
  { id: 's1', price: 15000 },
  { id: 's2', price: 5000 },
];

describe('manualBookingTotal', () => {
  it('sums the selected MIN prices (server re-prices)', () => {
    expect(manualBookingTotal(services, [])).toBe(0);
    expect(manualBookingTotal(services, ['s1'])).toBe(15000);
    expect(manualBookingTotal(services, ['s1', 's2'])).toBe(20000);
    expect(manualBookingTotal(services, ['gone'])).toBe(0);
  });
});

describe('combineDateTime', () => {
  it('combines the two inputs into a UTC ISO instant', () => {
    expect(combineDateTime('2026-12-01', '14:30')).toBe(
      '2026-12-01T14:30:00.000Z',
    );
  });

  it('the picked wall-clock IS salon time — offset-aware (MP3)', () => {
    expect(combineDateTime('2026-12-01', '14:30', 'Africa/Libreville')).toBe(
      '2026-12-01T13:30:00.000Z',
    );
  });

  it('rejects incomplete/malformed parts', () => {
    expect(combineDateTime('', '14:30')).toBeNull();
    expect(combineDateTime('2026-12-01', '')).toBeNull();
    expect(combineDateTime('01/12/2026', '14:30')).toBeNull();
    expect(combineDateTime('2026-12-01', '9h30')).toBeNull();
  });
});

describe('isFutureIso', () => {
  const now = new Date('2026-07-10T12:00:00.000Z');

  it('future ok; past and now rejected (the app guard)', () => {
    expect(isFutureIso('2026-07-10T12:30:00.000Z', now)).toBe(true);
    expect(isFutureIso('2026-07-10T11:59:00.000Z', now)).toBe(false);
    expect(isFutureIso('2026-07-10T12:00:00.000Z', now)).toBe(false);
    expect(isFutureIso('garbage', now)).toBe(false);
  });
});

describe('canSubmitManualBooking', () => {
  const ok = {
    serviceIds: ['s1'],
    dateTimeIso: '2026-12-01T14:30:00.000Z',
  };

  // docs/design/web-manual-booking-walk-in.md (owner Q1: like the app) — the
  // client is no longer a condition of the button: it is judged at submit,
  // under its field.
  it('needs ≥1 service + a datetime — not a name', () => {
    expect(canSubmitManualBooking(ok)).toBe(true);
    expect(canSubmitManualBooking({ ...ok, serviceIds: [] })).toBe(false);
    expect(canSubmitManualBooking({ ...ok, dateTimeIso: null })).toBe(false);
  });
});

describe('newClientNeedsPhone — the app\'s rule', () => {
  it('a new client needs a number…', () => {
    expect(newClientNeedsPhone({ picked: false, withoutNumber: false })).toBe(true);
  });
  it('…unless « Client sans numéro »', () => {
    expect(newClientNeedsPhone({ picked: false, withoutNumber: true })).toBe(false);
  });
  it('a picked client brings their own (or none)', () => {
    expect(newClientNeedsPhone({ picked: true, withoutNumber: false })).toBe(false);
  });
});

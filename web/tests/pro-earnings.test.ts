import { describe, expect, it } from 'vitest';
import { PERIODS, periodRange } from '../lib/pro/earnings';

/// periodRange buckets on SALON days (docs/design/timezone-salon-time.md §3
/// leak 1 — the old device-local midnight math drifted on non-UTC machines).
/// Every probe is an explicit instant, several deliberately shaped as a
/// foreign device's clock, so the suite is meaningful on any machine TZ.

describe('periodRange (salon-day buckets)', () => {
  // A Wednesday, 15:30 salon time.
  const now = new Date('2026-07-08T15:30:00Z');

  it('today: salon midnight → next salon midnight', () => {
    const r = periodRange('today', now)!;
    expect(r.startDate).toBe('2026-07-08T00:00:00.000Z');
    expect(r.endDate).toBe('2026-07-09T00:00:00.000Z');
  });

  it("today: the reproduced flake — 02:36 on a UTC+3 device is still the salon's July 7", () => {
    const r = periodRange('today', new Date('2026-07-08T02:36:00+03:00'))!;
    expect(r.startDate).toBe('2026-07-07T00:00:00.000Z');
    expect(r.endDate).toBe('2026-07-08T00:00:00.000Z');
  });

  it("today: a UTC−5 evening is already the salon's NEXT day", () => {
    const r = periodRange('today', new Date('2026-07-07T21:00:00-05:00'))!;
    expect(r.startDate).toBe('2026-07-08T00:00:00.000Z');
    expect(r.endDate).toBe('2026-07-09T00:00:00.000Z');
  });

  it('week: Monday-start, 7 salon days', () => {
    const r = periodRange('week', now)!;
    expect(r.startDate).toBe('2026-07-06T00:00:00.000Z'); // Monday
    expect(r.endDate).toBe('2026-07-13T00:00:00.000Z');
  });

  it('week: a Sunday belongs to the previous Monday', () => {
    const r = periodRange('week', new Date('2026-07-12T12:00:00Z'))!;
    expect(r.startDate).toBe('2026-07-06T00:00:00.000Z');
    expect(r.endDate).toBe('2026-07-13T00:00:00.000Z');
  });

  it('month: calendar month on salon days, even when the device is already in August', () => {
    // 00:30 August 1 on a UTC+3 device = 21:30Z July 31 → the salon July.
    const r = periodRange('month', new Date('2026-08-01T00:30:00+03:00'))!;
    expect(r.startDate).toBe('2026-07-01T00:00:00.000Z');
    expect(r.endDate).toBe('2026-08-01T00:00:00.000Z');
  });

  it('all → null (no range)', () => {
    expect(periodRange('all', now)).toBeNull();
  });

  it('exposes the four French tabs in the app’s order', () => {
    expect(PERIODS.map((p) => p.label)).toEqual([
      'Aujourd’hui',
      'Semaine',
      'Mois',
      'Tout',
    ]);
  });
});

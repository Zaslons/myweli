import { describe, expect, it } from 'vitest';
import { PERIODS, periodRange } from '../lib/pro/earnings';

describe('periodRange (parity 9.1 — the app’s earnings tabs)', () => {
  // A Wednesday, local time.
  const now = new Date(2026, 6, 8, 15, 30);

  it('today: local midnight → next midnight', () => {
    const r = periodRange('today', now)!;
    expect(new Date(r.startDate).getTime()).toBe(
      new Date(2026, 6, 8).getTime(),
    );
    expect(new Date(r.endDate).getTime()).toBe(new Date(2026, 6, 9).getTime());
  });

  it('week: Monday-start, 7 days (the app’s weekday - 1)', () => {
    const r = periodRange('week', now)!;
    expect(new Date(r.startDate).getTime()).toBe(
      new Date(2026, 6, 6).getTime(), // Monday July 6
    );
    expect(new Date(r.endDate).getTime()).toBe(
      new Date(2026, 6, 13).getTime(),
    );
  });

  it('week: a Sunday belongs to the week started the previous Monday', () => {
    const sunday = new Date(2026, 6, 12, 9, 0);
    const r = periodRange('week', sunday)!;
    expect(new Date(r.startDate).getTime()).toBe(
      new Date(2026, 6, 6).getTime(),
    );
  });

  it('month: calendar month', () => {
    const r = periodRange('month', now)!;
    expect(new Date(r.startDate).getTime()).toBe(
      new Date(2026, 6, 1).getTime(),
    );
    expect(new Date(r.endDate).getTime()).toBe(new Date(2026, 7, 1).getTime());
  });

  it('all: no range', () => {
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

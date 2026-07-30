import { describe, expect, it } from 'vitest';
import {
  SALON_TZ,
  addSalonDays,
  isSameSalonDay,
  salonDayKey,
  salonDayRange,
  salonFormatter,
  salonMidnight,
  salonOffsetDiffers,
  salonToday,
  salonWallClockToUtc,
  tzOffsetMinutes,
} from '../lib/time';

/// The salon-time seam (docs/design/timezone-salon-time.md §4). Everything
/// here passes explicit instants — never the process clock — so the suite is
/// meaningful on any machine TZ. Africa/Libreville (UTC+1, no DST) plays the
/// Wave-2 zone to prove the helpers are genuinely tz-parameterized.

const GABON = 'Africa/Libreville';

describe('salonDayKey / salonToday / isSameSalonDay', () => {
  it('keys the SALON day, not the device day, across midnight', () => {
    expect(salonDayKey(new Date('2026-07-13T23:30:00Z'))).toBe('2026-07-13');
    expect(salonDayKey(new Date('2026-07-14T00:10:00Z'))).toBe('2026-07-14');
    // The reproduced flake shape: 02:36 UTC+3 device = 23:36Z the day before.
    expect(salonDayKey(new Date('2026-07-08T02:36:00+03:00'))).toBe(
      '2026-07-07',
    );
  });

  it('a UTC+1 zone rolls the day at ITS midnight (Wave-2 proof)', () => {
    expect(salonDayKey(new Date('2026-07-13T23:30:00Z'), GABON)).toBe(
      '2026-07-14',
    );
    expect(salonDayKey(new Date('2026-07-13T22:30:00Z'), GABON)).toBe(
      '2026-07-13',
    );
  });

  it('isSameSalonDay across the boundary, both directions', () => {
    const lateNight = new Date('2026-07-13T23:50:00Z');
    const justAfter = new Date('2026-07-14T00:10:00Z');
    const earlySame = new Date('2026-07-13T00:10:00Z');
    expect(isSameSalonDay(lateNight, justAfter)).toBe(false);
    expect(isSameSalonDay(lateNight, earlySame)).toBe(true);
    // Same two instants, one zone east: both land on the 14th.
    expect(isSameSalonDay(lateNight, justAfter, GABON)).toBe(true);
  });

  it('salonToday is the day key of the passed instant', () => {
    expect(salonToday(new Date('2026-02-28T12:00:00Z'))).toBe('2026-02-28');
  });
});

describe('tzOffsetMinutes / salonMidnight / addSalonDays', () => {
  it('offsets come from the tz database, not a hardcoded zero', () => {
    const at = new Date('2026-07-13T12:00:00Z');
    expect(tzOffsetMinutes(at, SALON_TZ)).toBe(0);
    expect(tzOffsetMinutes(at, GABON)).toBe(60);
    expect(tzOffsetMinutes(at, 'America/New_York')).toBe(-240); // EDT
  });

  it('salonMidnight is the 00:00-salon-time instant of the containing day', () => {
    expect(salonMidnight(new Date('2026-07-13T23:30:00Z')).toISOString()).toBe(
      '2026-07-13T00:00:00.000Z',
    );
    // Gabon: 23:30Z is already the 14th there; its midnight = 23:00Z on the 13th.
    expect(
      salonMidnight(new Date('2026-07-13T23:30:00Z'), GABON).toISOString(),
    ).toBe('2026-07-13T23:00:00.000Z');
  });

  it('addSalonDays crosses month ends on salon days', () => {
    const d = new Date('2026-07-31T10:00:00Z');
    expect(addSalonDays(d, 1).toISOString()).toBe('2026-08-01T00:00:00.000Z');
    expect(addSalonDays(d, -31).toISOString()).toBe(
      '2026-06-30T00:00:00.000Z',
    );
  });
});

describe('salonDayRange', () => {
  it("today: the foreign-device flake shape lands in the SALON's day", () => {
    // 02:36 on a UTC+3 device = 2026-07-07T23:36Z → salon day July 7.
    const r = salonDayRange('today', new Date('2026-07-08T02:36:00+03:00'))!;
    expect(r.startDate).toBe('2026-07-07T00:00:00.000Z');
    expect(r.endDate).toBe('2026-07-08T00:00:00.000Z');
  });

  it('today: a UTC−5 evening is already the NEXT salon day', () => {
    // 21:00 UTC−5 = 2026-07-08T02:00Z → salon day July 8.
    const r = salonDayRange('today', new Date('2026-07-07T21:00:00-05:00'))!;
    expect(r.startDate).toBe('2026-07-08T00:00:00.000Z');
    expect(r.endDate).toBe('2026-07-09T00:00:00.000Z');
  });

  it('week: Monday-start, 7 salon days (Wednesday probe)', () => {
    const r = salonDayRange('week', new Date('2026-07-08T15:30:00Z'))!;
    expect(r.startDate).toBe('2026-07-06T00:00:00.000Z'); // Monday
    expect(r.endDate).toBe('2026-07-13T00:00:00.000Z');
  });

  it('week: a Sunday still belongs to the previous Monday', () => {
    const r = salonDayRange('week', new Date('2026-07-12T12:00:00Z'))!;
    expect(r.startDate).toBe('2026-07-06T00:00:00.000Z');
    expect(r.endDate).toBe('2026-07-13T00:00:00.000Z');
  });

  it('month: a device already in August at 00:30+03:00 stays in the salon July', () => {
    const r = salonDayRange('month', new Date('2026-08-01T00:30:00+03:00'))!;
    expect(r.startDate).toBe('2026-07-01T00:00:00.000Z');
    expect(r.endDate).toBe('2026-08-01T00:00:00.000Z');
  });

  it('all → null (no range)', () => {
    expect(salonDayRange('all', new Date('2026-07-08T12:00:00Z'))).toBeNull();
  });

  it('a UTC+1 salon gets ITS midnights (Wave-2 proof)', () => {
    const r = salonDayRange('today', new Date('2026-07-13T23:30:00Z'), GABON)!;
    expect(r.startDate).toBe('2026-07-13T23:00:00.000Z'); // 00:00 on the 14th, Libreville
    expect(r.endDate).toBe('2026-07-14T23:00:00.000Z');
  });
});

describe('salonWallClockToUtc (multi-pays MP3 — the offset-aware builder)', () => {
  it('a salon wall-clock becomes ITS UTC instant', () => {
    expect(
      salonWallClockToUtc('2026-07-20', 10 * 60 + 30).toISOString(),
    ).toBe('2026-07-20T10:30:00.000Z'); // Abidjan ≡ UTC
    expect(
      salonWallClockToUtc('2026-07-20', 10 * 60 + 30, GABON).toISOString(),
    ).toBe('2026-07-20T09:30:00.000Z'); // 10:30 Libreville = 09:30Z
  });

  it('round-trips with salonDayKey at the day edges', () => {
    // 00:00 Libreville on the 14th is 23:00Z on the 13th — and keys back
    // to the 14th in the salon zone.
    const midnight = salonWallClockToUtc('2026-07-14', 0, GABON);
    expect(midnight.toISOString()).toBe('2026-07-13T23:00:00.000Z');
    expect(salonDayKey(midnight, GABON)).toBe('2026-07-14');
  });

  it('handles a DST zone (future-proofing — none in the launch markets)', () => {
    // Paris summer (UTC+2): 09:00 wall = 07:00Z.
    expect(
      salonWallClockToUtc('2026-07-20', 9 * 60, 'Europe/Paris').toISOString(),
    ).toBe('2026-07-20T07:00:00.000Z');
    // Paris winter (UTC+1): 09:00 wall = 08:00Z.
    expect(
      salonWallClockToUtc('2026-01-20', 9 * 60, 'Europe/Paris').toISOString(),
    ).toBe('2026-01-20T08:00:00.000Z');
  });
});

describe('salonOffsetDiffers (the hint predicate)', () => {
  const at = new Date('2026-07-13T12:00:00Z');

  it('matrix: 0 → false; Paris/MSK/EST → true', () => {
    expect(salonOffsetDiffers(at, SALON_TZ, 0)).toBe(false);
    expect(salonOffsetDiffers(at, SALON_TZ, 60)).toBe(true); // Paris (CEST is 120)
    expect(salonOffsetDiffers(at, SALON_TZ, 180)).toBe(true); // MSK
    expect(salonOffsetDiffers(at, SALON_TZ, -300)).toBe(true); // EST
  });

  it('a device IN the salon zone offset never sees the hint', () => {
    expect(salonOffsetDiffers(at, GABON, 60)).toBe(false);
    expect(salonOffsetDiffers(at, GABON, 0)).toBe(true);
  });
});

describe('salonFormatter', () => {
  it('memoizes: identical options return the same instance', () => {
    const a = salonFormatter({ hour: '2-digit', minute: '2-digit' });
    const b = salonFormatter({ hour: '2-digit', minute: '2-digit' });
    expect(a).toBe(b);
  });

  it('always formats in the salon zone regardless of process TZ', () => {
    const f = salonFormatter({ hour: '2-digit', minute: '2-digit' });
    expect(f.format(new Date('2026-07-13T09:00:00Z'))).toBe('09:00');
    const g = salonFormatter({ hour: '2-digit', minute: '2-digit' }, GABON);
    expect(g.format(new Date('2026-07-13T09:00:00Z'))).toBe('10:00');
  });
});

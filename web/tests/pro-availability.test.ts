import { describe, expect, it } from 'vitest';
import {
  type Availability,
  toApi,
  toEditable,
  validateHours,
} from '../lib/pro/availability';

const base: Availability = {
  providerId: 'p1',
  weeklySchedule: {
    '0': [
      { startTime: '09:00', endTime: '12:00', isAvailable: true },
      { startTime: '14:00', endTime: '18:00', isAvailable: true }, // 2nd slot
    ],
    '5': [{ startTime: '10:00', endTime: '16:00', isAvailable: true }],
  },
  breaks: { '0': [{ startTime: '12:00', endTime: '14:00' }] },
  blockedDates: ['2026-07-14'],
  bufferMinutes: 10,
};

describe('pro availability helpers', () => {
  it('toEditable maps the first slot per day, Monday-first', () => {
    const days = toEditable(base);
    expect(days).toHaveLength(7);
    expect(days[0]).toMatchObject({ label: 'Lundi', open: true, start: '09:00', end: '12:00' });
    expect(days[1]).toMatchObject({ label: 'Mardi', open: false }); // no slots
    expect(days[5]).toMatchObject({ label: 'Samedi', open: true, start: '10:00' });
  });

  it('validateHours rejects end ≤ start on an open day', () => {
    const days = toEditable(base);
    days[0] = { ...days[0], end: '08:00' };
    expect(validateHours(days)).toMatch(/Lundi/);
    expect(validateHours(toEditable(base))).toBeNull();
  });

  it('toApi preserves base fields + extra slots; closes empty days', () => {
    const days = toEditable(base);
    days[0] = { ...days[0], start: '08:30' }; // edit Monday's first slot
    days[5] = { ...days[5], open: false }; // close Saturday
    const out = toApi(days, { ...base, bufferMinutes: 15 });

    // round-tripped fields
    expect(out.providerId).toBe('p1');
    expect(out.bufferMinutes).toBe(15);
    expect(out.breaks).toEqual(base.breaks);
    expect(out.blockedDates).toEqual(['2026-07-14']);
    // edited first slot + preserved 2nd slot
    expect(out.weeklySchedule['0'][0]).toMatchObject({ startTime: '08:30', endTime: '12:00' });
    expect(out.weeklySchedule['0'][1]).toMatchObject({ startTime: '14:00' });
    // closed day → empty
    expect(out.weeklySchedule['5']).toEqual([]);
  });
});

// Audit 3.4/3.8 — the generic schedule<->DayForm helpers.
import { daysToSchedule, scheduleToDays } from '../lib/pro/availability';

describe('scheduleToDays / daysToSchedule', () => {
  it('round-trips a schedule and preserves extra slots', () => {
    const ws = {
      '0': [
        { startTime: '09:00', endTime: '12:00' },
        { startTime: '14:00', endTime: '18:00' },
      ],
    };
    const days = scheduleToDays(ws);
    expect(days[0].open).toBe(true);
    expect(days[0].start).toBe('09:00');
    expect(days[1].open).toBe(false);

    const back = daysToSchedule(days, ws);
    expect(back['0']).toHaveLength(2); // the extra afternoon slot survives
    expect(back['1']).toBeUndefined(); // closed days omitted ({} = inherit)
  });

  it('defaults drive the editor placeholders (breaks: 12:30–13:30)', () => {
    const days = scheduleToDays(undefined, { start: '12:30', end: '13:30' });
    expect(days.every((d) => !d.open)).toBe(true);
    expect(days[0].start).toBe('12:30');
  });
});

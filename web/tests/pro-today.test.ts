import { describe, expect, it } from 'vitest';
import {
  type ProAppointment,
  todayCounts,
  todaysAppointments,
} from '../lib/pro/today';

const now = new Date('2026-06-28T12:00:00.000Z');
const items: ProAppointment[] = [
  { id: 'b', status: 'confirmed', appointmentDate: '2026-06-28T14:00:00.000Z' },
  { id: 'a', status: 'pending', appointmentDate: '2026-06-28T09:00:00.000Z' },
  { id: 'c', status: 'confirmed', appointmentDate: '2026-06-29T09:00:00.000Z' },
];

describe('pro today helpers', () => {
  it('keeps only today and sorts by time', () => {
    expect(todaysAppointments(items, now).map((a) => a.id)).toEqual(['a', 'b']);
  });

  it('counts pending/confirmed/total for today', () => {
    expect(todayCounts(items, now)).toEqual({
      total: 2,
      pending: 1,
      confirmed: 1,
    });
  });

  it("a UTC+1 salon buckets by ITS day, not the ISO's UTC prefix (MP3)", () => {
    const gabon = 'Africa/Libreville';
    const lateNight: ProAppointment[] = [
      // 23:30Z on the 27th = 00:30 on the 28th in Libreville.
      {
        id: 'x',
        status: 'confirmed',
        appointmentDate: '2026-06-27T23:30:00.000Z',
      },
      ...items,
    ];
    expect(
      todaysAppointments(lateNight, now, gabon).map((a) => a.id),
    ).toEqual(['x', 'a', 'b']);
    expect(todayCounts(lateNight, now, gabon).total).toBe(3);
    // Default (Abidjan ≡ UTC) keeps the old bucketing — bit-identical.
    expect(todaysAppointments(lateNight, now).map((a) => a.id)).toEqual([
      'a',
      'b',
    ]);
  });
});

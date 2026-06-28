import { describe, expect, it } from 'vitest';
import {
  addDays,
  addMonths,
  appointmentsOnDate,
  dateKey,
  daysWithBookings,
  filterList,
  monthMatrix,
} from '../lib/pro/agenda';
import type { ProAppointment } from '../lib/pro/today';

const now = new Date('2026-06-28T12:00:00.000Z'); // Sunday
const items: ProAppointment[] = [
  { id: 'a', status: 'pending', appointmentDate: '2026-06-28T14:00:00.000Z' },
  { id: 'b', status: 'confirmed', appointmentDate: '2026-06-28T09:00:00.000Z' },
  { id: 'c', status: 'completed', appointmentDate: '2026-06-20T09:00:00.000Z' },
  { id: 'd', status: 'confirmed', appointmentDate: '2026-06-30T09:00:00.000Z' },
];

describe('pro agenda helpers', () => {
  it('appointmentsOnDate filters one day and sorts by time', () => {
    expect(appointmentsOnDate(items, '2026-06-28').map((a) => a.id)).toEqual([
      'b',
      'a',
    ]);
    expect(appointmentsOnDate(items, '2026-07-01')).toEqual([]);
  });

  it('daysWithBookings collects distinct day keys', () => {
    expect(daysWithBookings(items)).toEqual(
      new Set(['2026-06-28', '2026-06-20', '2026-06-30']),
    );
  });

  it('filterList mirrors the app sub-tabs', () => {
    expect(filterList(items, 'today', now).map((a) => a.id)).toEqual(['b', 'a']);
    // upcoming = today-or-later AND pending/confirmed
    expect(filterList(items, 'upcoming', now).map((a) => a.id)).toEqual([
      'b',
      'a',
      'd',
    ]);
    expect(filterList(items, 'pending', now).map((a) => a.id)).toEqual(['a']);
    expect(filterList(items, 'all', now)).toHaveLength(4);
  });

  it('monthMatrix is 6×7 and Monday-start', () => {
    const m = monthMatrix(now);
    expect(m).toHaveLength(6);
    expect(m[0]).toHaveLength(7);
    // June 2026: the 1st is a Monday → first cell is June 1.
    expect(dateKey(m[0][0])).toBe('2026-06-01');
  });

  it('addDays / addMonths step correctly (UTC)', () => {
    expect(dateKey(addDays(now, 3))).toBe('2026-07-01');
    expect(dateKey(addMonths(now, 1))).toBe('2026-07-01'); // first of next month
  });
});

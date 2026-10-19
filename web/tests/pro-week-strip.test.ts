import { describe, expect, it } from 'vitest';

import type { JournalDay } from '../lib/pro/journal';
import type { ProAppointment } from '../lib/pro/today';
import {
  loadDotClass,
  weekCounts,
  weekOf,
  weekStripDay,
  weekStripLabel,
} from '../lib/pro/week-strip';

/// docs/design/web-pro-week-strip.md — the app's seven-day strip above « Ma
/// journée » (`pro_journal_screen.dart` `_WeekStrip`), on the web Journée.

const appt = (
  id: string,
  appointmentDate: string,
  status = 'confirmed',
): ProAppointment => ({
  id,
  status,
  appointmentDate,
  serviceIds: ['s1'],
  totalPrice: 10000,
});

const journal = (date: string, appointments: ProAppointment[]): JournalDay => ({
  date,
  hours: null,
  artists: [],
  appointments,
});

describe('weekOf — Monday to Sunday of the shown day', () => {
  it('a Wednesday', () => {
    expect(weekOf('2026-10-21')).toEqual([
      '2026-10-19',
      '2026-10-20',
      '2026-10-21',
      '2026-10-22',
      '2026-10-23',
      '2026-10-24',
      '2026-10-25',
    ]);
  });

  it('a Monday is its own first day, a Sunday its own last', () => {
    expect(weekOf('2026-10-19')[0]).toBe('2026-10-19');
    expect(weekOf('2026-10-25')[0]).toBe('2026-10-19');
    expect(weekOf('2026-10-25')[6]).toBe('2026-10-25');
  });

  it('across two months and two years', () => {
    expect(weekOf('2026-12-31')).toEqual([
      '2026-12-28',
      '2026-12-29',
      '2026-12-30',
      '2026-12-31',
      '2027-01-01',
      '2027-01-02',
      '2027-01-03',
    ]);
  });
});

describe('weekCounts — the bookings of each salon day, cancelled excluded', () => {
  const week = weekOf('2026-10-21');

  it('counts by the SALON’s day, not the instant’s UTC date', () => {
    // 23:30 UTC on the 20th is the 21st in Paris (UTC+2 in October).
    const items = [appt('a', '2026-10-20T23:30:00.000Z')];
    expect(weekCounts(items, week, 'Africa/Abidjan')['2026-10-20']).toBe(1);
    const paris = weekCounts(items, week, 'Europe/Paris');
    expect(paris['2026-10-20']).toBe(0);
    expect(paris['2026-10-21']).toBe(1);
  });

  it('a cancelled booking does not count (owner Q2: the dot is the load)', () => {
    const items = [
      appt('a', '2026-10-22T10:00:00.000Z', 'cancelled'),
      appt('b', '2026-10-23T10:00:00.000Z', 'pending'),
      appt('c', '2026-10-23T11:00:00.000Z', 'cancelled'),
    ];
    const c = weekCounts(items, week, 'Africa/Abidjan');
    expect(c['2026-10-22']).toBe(0);
    expect(c['2026-10-23']).toBe(1);
  });

  it('every day of the week has a number, bookings outside it are ignored', () => {
    const items = [appt('a', '2026-10-26T10:00:00.000Z')];
    const c = weekCounts(items, week, 'Africa/Abidjan');
    expect(Object.keys(c)).toEqual(week);
    expect(Object.values(c).every((n) => n === 0)).toBe(true);
  });

  it('the shown day is counted from its loaded journal day — it is the fresh one', () => {
    // The page's list was read once; the grid's quick-create reloaded only
    // the day. The day is right, the list is not.
    const items = [appt('a', '2026-10-21T10:00:00.000Z')];
    const day = journal('2026-10-21', [
      appt('a', '2026-10-21T10:00:00.000Z'),
      appt('new', '2026-10-21T14:00:00.000Z'),
      appt('gone', '2026-10-21T15:00:00.000Z', 'cancelled'),
    ]);
    expect(weekCounts(items, week, 'Africa/Abidjan', day)['2026-10-21']).toBe(2);
  });

  it('a journal day of ANOTHER date (the next one still loading) is not used', () => {
    const items = [appt('a', '2026-10-21T10:00:00.000Z')];
    const stale = journal('2026-10-20', [
      appt('x', '2026-10-20T10:00:00.000Z'),
      appt('y', '2026-10-20T11:00:00.000Z'),
    ]);
    const c = weekCounts(items, week, 'Africa/Abidjan', stale);
    expect(c['2026-10-21']).toBe(1);
    // …and the day it is about keeps its own count — it IS that day's rows.
    expect(c['2026-10-20']).toBe(2);
  });

  it('a journal day outside the week changes nothing', () => {
    const day = journal('2026-10-30', [appt('x', '2026-10-30T10:00:00.000Z')]);
    const c = weekCounts([], week, 'Africa/Abidjan', day);
    expect(Object.keys(c)).toEqual(week);
  });
});

describe('loadDotClass — longer with each booking, capped at five', () => {
  it('none at 0', () => {
    expect(loadDotClass(0)).toBeNull();
  });

  it('grows from 1 to 5, then stays', () => {
    const widths = [1, 2, 3, 4, 5].map(loadDotClass);
    expect(new Set(widths).size).toBe(5);
    expect(loadDotClass(9)).toBe(loadDotClass(5));
  });
});

describe('the words (owner Q3, approved as written)', () => {
  it('the group names its Monday', () => {
    expect(weekStripLabel(weekOf('2026-10-21'), 'Africa/Abidjan')).toBe(
      'Semaine du 19 octobre',
    );
  });

  it('a day shows « Lun 20 »; its name goes on with the month and the count', () => {
    expect(weekStripDay('2026-10-19', 3, false, 'Africa/Abidjan')).toEqual({
      short: 'Lun',
      day: '19',
      rest: 'octobre, 3 rendez-vous',
    });
  });

  it('nothing booked says so; today says so', () => {
    expect(weekStripDay('2026-10-25', 0, true, 'Africa/Abidjan').rest).toBe(
      'octobre, aucun rendez-vous, aujourd’hui',
    );
    expect(weekStripDay('2026-10-22', 1, false, 'Africa/Abidjan').rest).toBe(
      'octobre, 1 rendez-vous',
    );
  });

  it('a week across two months names each day’s own month', () => {
    const week = weekOf('2026-12-31');
    expect(weekStripDay(week[0], 0, false).short).toBe('Lun');
    expect(weekStripDay(week[0], 0, false).rest).toMatch(/^décembre,/);
    expect(weekStripDay(week[6], 0, false).short).toBe('Dim');
    expect(weekStripDay(week[6], 0, false).rest).toMatch(/^janvier,/);
  });
});

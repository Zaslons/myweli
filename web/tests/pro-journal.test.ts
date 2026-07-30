import { describe, expect, it } from 'vitest';
import {
  type JournalDay,
  axisHeight,
  blockBox,
  breakBands,
  columnsFor,
  hhmm,
  hourTicks,
  isDraggable,
  isoAt,
  minutesOfDay,
  nowLineTop,
  parseHhmm,
  snapToQuarter,
  statusKey,
} from '../lib/pro/journal';
import type { ProAppointment } from '../lib/pro/today';

// Module `journal` J1 (docs/design/journal-j1-grid.md §3): pure grid geometry.
const appt = (over: Partial<ProAppointment> = {}): ProAppointment => ({
  id: 'a1',
  status: 'confirmed',
  appointmentDate: '2026-07-13T10:00:00.000Z',
  durationMinutes: 60,
  ...over,
});

describe('journal geometry', () => {
  it('parses/formats HH:mm and minutes-of-day (UTC)', () => {
    expect(parseHhmm('09:30')).toBe(570);
    expect(hhmm(570)).toBe('09:30');
    expect(minutesOfDay('2026-07-13T14:15:00.000Z')).toBe(14 * 60 + 15);
  });

  it('snaps to the 15-minute grid', () => {
    expect(snapToQuarter(607)).toBe(600); // 10:07 → 10:00
    expect(snapToQuarter(608)).toBe(615); // 10:08 → 10:15
  });

  it('positions a block by start + duration (min height enforced)', () => {
    const open = parseHhmm('09:00'); // 540
    expect(blockBox(appt(), open)).toEqual({ top: 60, height: 60 });
    // 15-min service keeps a clickable min height (24px) though dur=15.
    expect(blockBox(appt({ durationMinutes: 15 }), open).height).toBe(24);
  });

  it('axis height, hour ticks and break bands', () => {
    const hours = { open: '09:00', close: '12:00', breaks: [{ start: '10:30', end: '11:00' }] };
    expect(axisHeight(hours)).toBe(180);
    expect(hourTicks(hours).map((t) => t.label)).toEqual(['09:00', '10:00', '11:00', '12:00']);
    expect(breakBands(hours)).toEqual([{ top: 90, height: 30 }]);
  });

  it('now-line only shows for today within hours', () => {
    const hours = { open: '09:00', close: '18:00', breaks: [] };
    const at = new Date('2026-07-13T10:00:00.000Z');
    expect(nowLineTop(at, '2026-07-13', hours)).toBe(60);
    // Other day → null.
    expect(nowLineTop(at, '2026-07-12', hours)).toBeNull();
    // Before open → null.
    expect(nowLineTop(new Date('2026-07-13T07:00:00.000Z'), '2026-07-13', hours)).toBeNull();
  });

  it('isoAt snaps a drop to a SALON quarter-hour (offset-aware — MP3)', () => {
    expect(isoAt('2026-07-13', 607)).toBe('2026-07-13T10:00:00.000Z');
    expect(isoAt('2026-07-13', 619)).toBe('2026-07-13T10:15:00.000Z'); // 10:19→10:15
    // A 10:00 drop on a Libreville grid is 09:00Z — the wall-clock is the
    // salon's, not UTC.
    expect(isoAt('2026-07-13', 600, 'Africa/Libreville')).toBe(
      '2026-07-13T09:00:00.000Z',
    );
  });

  it('minutesOfDay follows the salon zone (MP3)', () => {
    expect(
      minutesOfDay('2026-07-13T14:15:00.000Z', 'Africa/Libreville'),
    ).toBe(15 * 60 + 15);
  });

  it('the now-line follows the salon zone (MP3)', () => {
    const hours = { open: '09:00', close: '18:00', breaks: [] };
    // 08:30Z = 09:30 Libreville → 30 px past open on ITS 13th.
    const at = new Date('2026-07-13T08:30:00.000Z');
    expect(nowLineTop(at, '2026-07-13', hours, 'Africa/Libreville')).toBe(30);
    expect(nowLineTop(at, '2026-07-13', hours)).toBeNull(); // Abidjan: before open
  });

  it('statusKey derives « arrived » from confirmed + arrivedAt', () => {
    expect(statusKey(appt())).toBe('confirmed');
    expect(statusKey(appt({ arrivedAt: '2026-07-13T10:05:00.000Z' }))).toBe('arrived');
    expect(statusKey(appt({ status: 'noShow' }))).toBe('noShow');
  });

  it('draggable only while pending/confirmed', () => {
    expect(isDraggable(appt({ status: 'pending' }))).toBe(true);
    expect(isDraggable(appt({ status: 'confirmed' }))).toBe(true);
    expect(isDraggable(appt({ status: 'completed' }))).toBe(false);
    expect(isDraggable(appt({ status: 'cancelled' }))).toBe(false);
  });

  it('columns = artists + a « Sans artiste » column when any unassigned', () => {
    const base: JournalDay = {
      date: '2026-07-13',
      hours: null,
      artists: [{ id: 'ar1', name: 'Awa' }],
      appointments: [],
    };
    expect(columnsFor(base).map((c) => c.id)).toEqual(['ar1']);
    expect(
      columnsFor({ ...base, appointments: [appt({ artistId: null })] }).map(
        (c) => c.name,
      ),
    ).toEqual(['Awa', 'Sans artiste']);
    // No artists at all → a single « Salon » column.
    expect(
      columnsFor({ ...base, artists: [], appointments: [appt({ artistId: 'ar1' })] })
        .map((c) => c.name),
    ).toEqual(['Salon']);
  });
});

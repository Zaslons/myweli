import { describe, expect, it } from 'vitest';

import { agendaQuery, readAgenda } from '../lib/pro/agenda-url';
import type { JournalDay } from '../lib/pro/journal';
import type { ProAppointment } from '../lib/pro/today';
import {
  dayBands,
  filterArtist,
  lanesFor,
  weekArtists,
  weekAxis,
} from '../lib/pro/week-view';

/// docs/design/web-pro-week-view.md — the « Semaine » grid's pure parts.

const appt = (id: string, iso: string, minutes: number, artistId?: string): ProAppointment => ({
  id,
  status: 'confirmed',
  appointmentDate: iso,
  serviceIds: ['s1'],
  totalPrice: 1000,
  durationMinutes: minutes,
  ...(artistId ? { artistId } : {}),
});

const day = (date: string, hours: JournalDay['hours'], appointments: ProAppointment[] = [], artists = [{ id: 'ar1', name: 'Awa' }]): JournalDay => ({
  date,
  hours,
  artists,
  appointments,
});

describe('weekAxis — one axis for the seven days', () => {
  it('from the earliest opening to the latest closing of the open days', () => {
    const axis = weekAxis([
      day('2026-10-19', { open: '09:00', close: '18:00', breaks: [] }),
      day('2026-10-20', { open: '08:00', close: '17:00', breaks: [] }),
      day('2026-10-21', null),
      day('2026-10-22', { open: '10:00', close: '20:00', breaks: [] }),
    ]);
    expect(axis).toEqual({ open: '08:00', close: '20:00', breaks: [] });
  });

  it('closed all week: the Journée’s neutral axis', () => {
    expect(weekAxis([day('2026-10-19', null)])).toEqual({ open: '08:00', close: '20:00', breaks: [] });
  });
});

describe('dayBands — what is not open, on the week’s axis', () => {
  it('before opening, the breaks, after closing (px from the axis top)', () => {
    const axis = { open: '08:00', close: '20:00', breaks: [] };
    const bands = dayBands(
      day('2026-10-19', { open: '10:00', close: '17:00', breaks: [{ start: '13:00', end: '14:00' }] }),
      axis,
    );
    expect(bands).toEqual([
      { top: 0, height: 120 },
      { top: 300, height: 60 },
      { top: 540, height: 180 },
    ]);
  });

  it('a closed day is one band, the whole axis', () => {
    const axis = { open: '08:00', close: '20:00', breaks: [] };
    expect(dayBands(day('2026-10-21', null), axis)).toEqual([{ top: 0, height: 720 }]);
  });
});

describe('lanesFor — simultaneous bookings share the column side by side', () => {
  it('two overlapping take a half each; the next one alone takes it all', () => {
    const lanes = lanesFor(
      [
        appt('a', '2026-10-19T09:00:00.000Z', 60, 'ar1'),
        appt('b', '2026-10-19T09:30:00.000Z', 60, 'ar2'),
        appt('c', '2026-10-19T11:00:00.000Z', 60, 'ar1'),
      ],
      'Africa/Abidjan',
    );
    expect(lanes.get('a')).toEqual({ lane: 0, lanes: 2 });
    expect(lanes.get('b')).toEqual({ lane: 1, lanes: 2 });
    expect(lanes.get('c')).toEqual({ lane: 0, lanes: 1 });
  });

  it('back to back is not simultaneous', () => {
    const lanes = lanesFor(
      [
        appt('a', '2026-10-19T09:00:00.000Z', 60),
        appt('b', '2026-10-19T10:00:00.000Z', 60),
      ],
      'Africa/Abidjan',
    );
    expect(lanes.get('a')).toEqual({ lane: 0, lanes: 1 });
    expect(lanes.get('b')).toEqual({ lane: 0, lanes: 1 });
  });

  it('three at once: three lanes; a freed lane is reused', () => {
    const lanes = lanesFor(
      [
        appt('a', '2026-10-19T09:00:00.000Z', 120),
        appt('b', '2026-10-19T09:00:00.000Z', 30),
        appt('c', '2026-10-19T09:15:00.000Z', 60),
        appt('d', '2026-10-19T09:30:00.000Z', 30),
      ],
      'Africa/Abidjan',
    );
    expect(lanes.get('a')!.lanes).toBe(3);
    expect(new Set(['a', 'b', 'c'].map((k) => lanes.get(k)!.lane)).size).toBe(3);
    expect(lanes.get('d')!.lane).toBe(lanes.get('b')!.lane); // b ended at 09:30
  });
});

describe('the artist filter', () => {
  const week = [
    day('2026-10-19', null, [appt('a', '2026-10-19T09:00:00.000Z', 30, 'ar1'), appt('n', '2026-10-19T10:00:00.000Z', 30)]),
    day('2026-10-20', null, [], [{ id: 'ar1', name: 'Awa' }, { id: 'ar2', name: 'Mia' }]),
  ];

  it('the week’s artists, and « Sans artiste » when a booking has none', () => {
    expect(weekArtists(week)).toEqual([
      { id: 'ar1', name: 'Awa' },
      { id: 'ar2', name: 'Mia' },
      { id: '', name: 'Sans artiste' },
    ]);
  });

  it('« Tous » keeps everything; an artist keeps theirs; « Sans artiste » the rest', () => {
    const all = week[0].appointments;
    expect(filterArtist(all, null)).toHaveLength(2);
    expect(filterArtist(all, 'ar1').map((a) => a.id)).toEqual(['a']);
    expect(filterArtist(all, '').map((a) => a.id)).toEqual(['n']);
  });
});

describe('the address — ?vue=semaine', () => {
  const today = '2026-10-19';
  it('reads the week view and its day', () => {
    expect(readAgenda('?vue=semaine&jour=2026-10-21', today)).toMatchObject({
      view: 'week',
      journalDate: '2026-10-21',
    });
  });
  it('writes it, the day only when it is not today', () => {
    const base = { view: 'week' as const, selected: today, listTab: 'today' as const };
    expect(agendaQuery({ ...base, journalDate: '2026-10-28' }, today)).toBe('?vue=semaine&jour=2026-10-28');
    expect(agendaQuery({ ...base, journalDate: today }, today)).toBe('?vue=semaine');
  });
});

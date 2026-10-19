import { describe, expect, it } from 'vitest';
import {
  type Availability,
  SCHEDULE_PRESETS,
  applyBlockedChange,
  applyPreset,
  blockedChange,
  blockedConfirm,
  blockedDayKey,
  blockedPickerSummary,
  blockedSavedSummary,
  copyDayToAll,
  nextRange,
  presetMatches,
  toApi,
  toEditable,
  validateHours,
} from '../lib/pro/availability';

/// Split working hours and bulk blocked dates — the pure half
/// (docs/design/web-pro-availability-ranges.md). The web used to show and edit
/// only a day's FIRST range (`slots[0]`, the rest kept invisible by
/// `slice(1)`), and to crash on a blocked date the app wrote.

const W = (hhmm: string) => `2024-01-01T${hhmm}:00.000Z`;
const slot = (a: string, b: string) => ({ startTime: W(a), endTime: W(b), isAvailable: true });

const base: Availability = {
  providerId: 'p1',
  weeklySchedule: {
    '0': [slot('09:00', '12:00'), slot('14:00', '18:00')], // closed at noon
    '5': [slot('10:00', '16:00')],
  },
  breaks: { '0': [{ startTime: W('12:00'), endTime: W('13:00') }] },
  blockedDates: ['2026-12-25'],
  bufferMinutes: 10,
};

describe('split working hours — every range, both ways', () => {
  it('toEditable reads ALL of a day’s ranges, in order', () => {
    const days = toEditable(base);
    expect(days[0]).toMatchObject({
      label: 'Lundi',
      open: true,
      ranges: [
        { start: '09:00', end: '12:00' },
        { start: '14:00', end: '18:00' },
      ],
    });
    expect(days[1]).toMatchObject({ label: 'Mardi', open: false, ranges: [] });
  });

  it('the round-trip is byte-identical to what the server sent', () => {
    // Closed days go back as [] — as they always did (`toApi`'s closed rule).
    expect(toApi(toEditable(base), base).weeklySchedule).toEqual({
      ...base.weeklySchedule,
      '1': [],
      '2': [],
      '3': [],
      '4': [],
      '6': [],
    });
  });

  it('an edited afternoon is written — it is no longer invisible', () => {
    const days = toEditable(base);
    days[0] = { ...days[0], ranges: [days[0].ranges[0], { start: '15:00', end: '19:00' }] };
    expect(toApi(days, base).weeklySchedule['0']).toEqual([
      slot('09:00', '12:00'),
      slot('15:00', '19:00'),
    ]);
  });

  it('ranges are written sorted by their start', () => {
    const days = toEditable(base);
    days[0] = { ...days[0], ranges: [...days[0].ranges].reverse() };
    expect(toApi(days, base).weeklySchedule['0'][0].startTime).toBe(W('09:00'));
  });

  it('a closed day writes nothing — and keeps its ranges to reopen', () => {
    const days = toEditable(base);
    const closed = { ...days[0], open: false };
    expect(toApi([closed, ...days.slice(1)], base).weeklySchedule['0']).toEqual([]);
    expect(closed.ranges).toHaveLength(2);
  });

  it('every other field rides along untouched', () => {
    const out = toApi(toEditable(base), { ...base, bufferMinutes: 15 });
    expect(out.breaks).toEqual(base.breaks);
    expect(out.blockedDates).toEqual(base.blockedDates);
    expect(out.bufferMinutes).toBe(15);
  });
});

describe('validateHours — each range, and no two that overlap', () => {
  it('an end at or before its start is refused, naming the day', () => {
    const days = toEditable(base);
    days[0] = { ...days[0], ranges: [{ start: '09:00', end: '09:00' }] };
    expect(validateHours(days)).toBe('Lundi : l’heure de fin doit être après le début.');
  });

  it('two ranges that overlap are refused (H4)', () => {
    const days = toEditable(base);
    days[0] = {
      ...days[0],
      ranges: [
        { start: '09:00', end: '13:00' },
        { start: '12:00', end: '18:00' },
      ],
    };
    expect(validateHours(days)).toBe('Lundi : deux plages se chevauchent.');
  });

  it('touching ranges are fine — one ends at 12:00, the next starts at 12:00', () => {
    const days = toEditable(base);
    days[0] = {
      ...days[0],
      ranges: [
        { start: '09:00', end: '12:00' },
        { start: '12:00', end: '18:00' },
      ],
    };
    expect(validateHours(days)).toBeNull();
  });

  it('order does not hide an overlap', () => {
    const days = toEditable(base);
    days[0] = {
      ...days[0],
      ranges: [
        { start: '14:00', end: '18:00' },
        { start: '09:00', end: '15:00' },
      ],
    };
    expect(validateHours(days)).toBe('Lundi : deux plages se chevauchent.');
  });

  it('a closed day is not checked', () => {
    const days = toEditable(base);
    days[1] = { ...days[1], open: false, ranges: [{ start: '18:00', end: '09:00' }] };
    expect(validateHours(days)).toBeNull();
  });
});

describe('nextRange — what « Ajouter une plage » proposes', () => {
  it('the first range: 09:00–18:00', () => {
    expect(nextRange([])).toEqual({ start: '09:00', end: '18:00' });
  });

  it('one hour after the last end, four hours long', () => {
    expect(nextRange([{ start: '09:00', end: '12:00' }])).toEqual({ start: '13:00', end: '17:00' });
  });

  it('never past 23:59', () => {
    expect(nextRange([{ start: '09:00', end: '20:00' }])).toEqual({ start: '21:00', end: '23:59' });
  });

  it('less than an hour left: it starts where the last one ends', () => {
    expect(nextRange([{ start: '09:00', end: '23:30' }])).toEqual({ start: '23:30', end: '23:59' });
  });

  it('nothing left: null (the button goes inactive)', () => {
    expect(nextRange([{ start: '09:00', end: '23:59' }])).toBeNull();
  });
});

describe('models and copy with several ranges', () => {
  it('applyPreset: ONE range on each model day, every other day closed', () => {
    const next = applyPreset(toEditable(base), SCHEDULE_PRESETS[0]); // Mar–Sam · 9h–18h
    expect(next[0].open).toBe(false);
    expect(next[1]).toMatchObject({ open: true, ranges: [{ start: '09:00', end: '18:00' }] });
  });

  it('presetMatches: a second range unlights the chip', () => {
    const preset = SCHEDULE_PRESETS[0];
    const applied = applyPreset(toEditable(base), preset);
    expect(presetMatches(applied, preset)).toBe(true);
    applied[1] = { ...applied[1], ranges: [...applied[1].ranges, { start: '19:00', end: '20:00' }] };
    expect(presetMatches(applied, preset)).toBe(false);
  });

  it('copyDayToAll copies EVERY range — as independent copies', () => {
    const next = copyDayToAll(toEditable(base), 0);
    for (const d of next) {
      expect(d.open).toBe(true);
      expect(d.ranges).toEqual([
        { start: '09:00', end: '12:00' },
        { start: '14:00', end: '18:00' },
      ]);
    }
    next[3].ranges[0].start = '10:00';
    expect(next[4].ranges[0].start).toBe('09:00');
  });
});

describe('blocked dates — both stored formats are one SALON day', () => {
  it('a day string is that day', () => {
    expect(blockedDayKey('2026-12-25', 'Africa/Abidjan')).toBe('2026-12-25');
    expect(blockedDayKey('2026-12-25', 'Africa/Libreville')).toBe('2026-12-25');
  });

  it('the app’s salon-midnight instant is the salon’s day (UTC and UTC+1)', () => {
    expect(blockedDayKey('2026-12-25T00:00:00.000Z', 'Africa/Abidjan')).toBe('2026-12-25');
    expect(blockedDayKey('2026-12-24T23:00:00.000Z', 'Africa/Libreville')).toBe('2026-12-25');
  });

  it('garbage is null, never a throw', () => {
    expect(blockedDayKey('nope', 'Africa/Abidjan')).toBeNull();
  });

  it('a change keeps untouched entries byte-identical, adds salon midnight in UTC, removes by day', () => {
    const current = ['2026-12-25', '2026-12-31T23:00:00.000Z']; // 2027-01-01 in Libreville
    expect(
      applyBlockedChange(current, { added: ['2027-02-14'], removed: ['2027-01-01'] }, 'Africa/Libreville'),
    ).toEqual(['2026-12-25', '2027-02-13T23:00:00.000Z']);
  });

  it('a day already blocked is not added twice', () => {
    expect(
      applyBlockedChange(['2026-12-25T00:00:00.000Z'], { added: ['2026-12-25'], removed: [] }, 'Africa/Abidjan'),
    ).toEqual(['2026-12-25T00:00:00.000Z']);
  });

  it('blockedChange: what the picker adds and removes', () => {
    expect(blockedChange(new Set(['a', 'b']), new Set(['b', 'c']))).toEqual({ added: ['c'], removed: ['a'] });
  });
});

describe('the app’s words, verbatim (D3, D6, D7)', () => {
  it('the picker’s live summary', () => {
    expect(blockedPickerSummary(0, { added: [], removed: [] })).toEqual({
      state: 'Touchez les jours à bloquer.',
      delta: '',
    });
    expect(blockedPickerSummary(3, { added: ['a', 'b'], removed: ['c'] })).toEqual({
      state: '3 dates bloquées',
      delta: '2 ajoutées · 1 retirée',
    });
    expect(blockedPickerSummary(0, { added: [], removed: ['c'] }).state).toBe(
      'Toutes vos dates bloquées seront retirées.',
    );
  });

  it('the confirmation names the direction', () => {
    const fmt = (k: string) => `«${k}»`;
    expect(blockedConfirm({ added: ['d1'], removed: [] }, fmt)).toEqual({
      title: 'Bloquer cette date ?',
      lines: ['Le «d1», votre salon n’acceptera aucune réservation.'],
      confirm: 'Bloquer',
      destructive: true,
    });
    expect(blockedConfirm({ added: ['d1', 'd2'], removed: [] }, fmt)).toEqual({
      title: 'Bloquer ces dates ?',
      lines: ['Votre salon n’acceptera aucune réservation pendant ces 2 journées.'],
      confirm: 'Bloquer 2 dates',
      destructive: true,
    });
    expect(blockedConfirm({ added: [], removed: ['d1'] }, fmt)).toEqual({
      title: 'Débloquer cette date ?',
      lines: ['Le «d1», votre salon acceptera de nouveau des réservations.'],
      confirm: 'Débloquer',
      destructive: false,
    });
    expect(blockedConfirm({ added: [], removed: ['d1', 'd2', 'd3'] }, fmt)).toEqual({
      title: 'Débloquer ces dates ?',
      lines: ['Votre salon acceptera de nouveau des réservations pendant ces 3 journées.'],
      confirm: 'Débloquer 3 dates',
      destructive: false,
    });
    expect(blockedConfirm({ added: ['d1', 'd2'], removed: ['d3'] }, fmt)).toEqual({
      title: 'Modifier vos dates bloquées ?',
      lines: ['2 dates seront bloquées', '1 date sera débloquée'],
      confirm: 'Enregistrer',
      destructive: true,
    });
  });

  it('the line after the write', () => {
    expect(blockedSavedSummary({ added: ['a', 'b'], removed: ['c'] })).toBe(
      '2 dates bloquées · 1 date débloquée',
    );
  });
});

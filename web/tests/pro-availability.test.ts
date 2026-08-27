import { describe, expect, it } from 'vitest';
import {
  type Availability,
  HORIZON_PRESETS,
  NOTICE_PRESETS,
  SCHEDULE_PRESETS,
  applyPreset,
  copyDayToAll,
  horizonLabel,
  noticeLabel,
  presetMatches,
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

describe('A14d — the bookable window survives a save', () => {
  it('toApi round-trips the window like every other base field', () => {
    // `save()` builds the request from `{...base, bufferMinutes, blockedDates}`
    // and stores the SAME object into `base` afterwards, so a field that does
    // not ride inside that spread is lost on the next save. `breaks` already
    // demonstrates the failure mode (see the setBase test below); the window
    // must not join it.
    const out = toApi(toEditable(base), {
      ...base,
      bookingHorizonDays: 30,
      minimumNoticeMinutes: 120,
    });
    expect(out.bookingHorizonDays).toBe(30);
    expect(out.minimumNoticeMinutes).toBe(120);
  });

  it('no preset pair can leave the salon unbookable', () => {
    // The server refuses a notice reaching past the horizon as invalid_input.
    for (const days of HORIZON_PRESETS) {
      for (const minutes of NOTICE_PRESETS) {
        expect(minutes).toBeLessThanOrEqual(days * 24 * 60);
      }
    }
  });

  it('every preset is inside the contract bounds', () => {
    for (const d of HORIZON_PRESETS) {
      expect(d).toBeGreaterThanOrEqual(1);
      expect(d).toBeLessThanOrEqual(730);
    }
    for (const m of NOTICE_PRESETS) {
      expect(m).toBeGreaterThanOrEqual(0);
      expect(m).toBeLessThanOrEqual(10080);
    }
  });

  it('the labels match mobile word for word', () => {
    expect(HORIZON_PRESETS.map(horizonLabel)).toEqual([
      '1 mois',
      '3 mois',
      '6 mois',
      '1 an',
    ]);
    expect(NOTICE_PRESETS.map(noticeLabel)).toEqual([
      'Aucun',
      '1 h',
      '12 h',
      '24 h',
    ]);
  });
});

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
    // Edited first slot, now in the WIRE format (Q1): the edit comes from an
    // `<input type="time">` as '08:30' and leaves as a date-time, because that
    // is what `openapi.yaml:4033` types and what the server accepts. This
    // assertion used to read `startTime: '08:30'` — it encoded the defect.
    expect(out.weeklySchedule['0'][0]).toMatchObject({
      startTime: '2024-01-01T08:30:00.000Z',
      endTime: '2024-01-01T12:00:00.000Z',
    });
    // The preserved 2nd slot is passed through from `base` untouched, so it
    // keeps whatever shape it arrived in — the round-trip does not rewrite
    // slots the pro did not edit.
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

/// **The wire format is a date-time, and this suite used to assert the wrong
/// one.** `openapi.yaml:4033-4036` types `TimeSlot.startTime` as
/// `format: date-time` — "Only the time-of-day is significant (placeholder
/// date)" — and the server normalises to `2024-01-01T09:00:00.000Z`. The mobile
/// app complies (`availability.dart:21`, `toIso8601String()`); the backend
/// validates with `DateTime.tryParse` and answers 400 `invalid_input` to
/// anything else (`provider_catalog_service.dart:713`).
///
/// The web sent `'09:00'` and read the server's ISO straight into an
/// `<input type="time">`, so BOTH directions were broken — and every fixture
/// above uses `'09:00'`, which is why 555 green tests said nothing. Found by
/// building the Q1 funnel smoke against a real server, not by a unit test.
describe('the wire format is a date-time, both directions (Q1)', () => {
  const wire: Availability = {
    providerId: 'p1',
    weeklySchedule: {
      '0': [
        {
          startTime: '2024-01-01T09:00:00.000Z',
          endTime: '2024-01-01T18:00:00.000Z',
          isAvailable: true,
        },
      ],
    },
    blockedDates: [],
    bufferMinutes: 0,
  };

  it('READ: a server date-time becomes HH:mm for the time input', () => {
    // `<input type="time">` accepts only HH:mm (`DayHoursEditor.tsx:52`), so an
    // ISO string renders the field blank and the pro sees no hours at all.
    const d = toEditable(wire)[0];
    expect(d.start).toBe('09:00');
    expect(d.end).toBe('18:00');
  });

  it('WRITE: HH:mm becomes a date-time the server accepts', () => {
    const days = toEditable(wire);
    const slot = toApi(days, wire).weeklySchedule['0'][0];
    // Parseable as a date-time — the exact predicate the server applies.
    expect(Number.isNaN(Date.parse(slot.startTime))).toBe(false);
    expect(Number.isNaN(Date.parse(slot.endTime))).toBe(false);
  });

  it('and the round-trip is byte-identical to what the server sent', () => {
    // The pair that makes the two above non-degenerate: a converter that
    // mangles the value could satisfy both and still lose the salon's hours.
    const days = toEditable(wire);
    expect(toApi(days, wire).weeklySchedule['0'][0].startTime).toBe(
      '2024-01-01T09:00:00.000Z',
    );
  });

  it('a fresh salon with no hours still sends a date-time, not the raw default', () => {
    // The onboarding case, and the one that actually broke: with no stored
    // slots `toEditable` falls back to '09:00', which used to go on the wire
    // verbatim and earn a 400 — so a web-onboarded salon could never satisfy
    // the `availability` publish-gate key, and could never go live.
    const empty: Availability = { ...wire, weeklySchedule: {} };
    const days = toEditable(empty).map((d) => ({ ...d, open: true }));
    const slot = toApi(days, empty).weeklySchedule['0'][0];
    expect(Number.isNaN(Date.parse(slot.startTime))).toBe(false);
  });
});

describe('the « Horaires » models (availability-presets.md)', () => {
  it('invariants: end > start, days a non-empty subset of 0..6, labels unique', () => {
    for (const p of SCHEDULE_PRESETS) {
      expect(p.start < p.end, p.label).toBe(true);
      expect(p.days.length, p.label).toBeGreaterThan(0);
      expect(p.days.every((d) => d >= 0 && d <= 6), p.label).toBe(true);
    }
    const labels = SCHEDULE_PRESETS.map((p) => p.label);
    expect(new Set(labels).size).toBe(labels.length);
  });

  it('applyPreset opens the model days at its hours and CLOSES the rest', () => {
    const rows = toEditable(base); // Lundi + Samedi open from the fixture
    const preset = SCHEDULE_PRESETS[0]; // Mar–Sam · 9h–18h
    const next = applyPreset(rows, preset);
    expect(next).toHaveLength(7);
    for (let i = 0; i < 7; i++) {
      if (preset.days.includes(i)) {
        expect(next[i].open, `day ${i}`).toBe(true);
        expect(next[i].start).toBe('09:00');
        expect(next[i].end).toBe('18:00');
      } else {
        // A model is the whole week: Lundi (open in the fixture, outside
        // Mar–Sam) must CLOSE, or a lit chip would misname the schedule.
        expect(next[i].open, `day ${i}`).toBe(false);
      }
    }
  });

  it('presetMatches is honest: exact model only, any edit unlights', () => {
    const preset = SCHEDULE_PRESETS[0];
    const applied = applyPreset(toEditable(base), preset);
    expect(presetMatches(applied, preset)).toBe(true);
    for (const other of SCHEDULE_PRESETS.slice(1)) {
      expect(presetMatches(applied, other), other.label).toBe(false);
    }
    // Edited closing hour.
    const edited = applied.map((d, i) => (i === 2 ? { ...d, end: '19:00' } : d));
    expect(presetMatches(edited, preset)).toBe(false);
    // A day outside the model opened.
    const sunday = applied.map((d, i) => (i === 6 ? { ...d, open: true } : d));
    expect(presetMatches(sunday, preset)).toBe(false);
  });

  it('copyDayToAll copies {open, start, end} onto every row, keys intact', () => {
    const rows = toEditable(base);
    const next = copyDayToAll(rows, 5); // Samedi 10:00–16:00
    for (let i = 0; i < 7; i++) {
      expect(next[i].open, `day ${i}`).toBe(true);
      expect(next[i].start).toBe('10:00');
      expect(next[i].end).toBe('16:00');
      expect(next[i].key).toBe(rows[i].key);
      expect(next[i].label).toBe(rows[i].label);
    }
  });

  it('the copy leaves each day\'s EXTRA ranges to survive the save', () => {
    // The one-range-per-day trap honoured: Lundi's second range rides
    // `toApi`'s slice(1) from base, copy or no copy.
    const out = toApi(copyDayToAll(toEditable(base), 5), base);
    expect(out.weeklySchedule['0']).toHaveLength(2);
    expect(out.weeklySchedule['0'][0].startTime).toContain('10:00');
    expect(out.weeklySchedule['0'][1].startTime).toContain('14:00');
  });
});

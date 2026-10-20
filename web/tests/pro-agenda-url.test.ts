import { describe, expect, it } from 'vitest';
import {
  agendaParams,
  agendaQuery,
  isDayKey,
  readAgenda,
} from '../lib/pro/agenda-url';

/// docs/design/web-pro-agenda-url.md — the agenda's address says what the salon
/// is looking at, so coming back from a booking (« ← Rendez-vous », Back) or a
/// reload lands where it was. Owner-approved words (Q1): `vue`, `jour`,
/// `filtre`, French values without accents; the defaults are never written.

const TODAY = '2026-10-19';
const DEFAULTS = {
  view: 'journal',
  journalDate: TODAY,
  selected: TODAY,
  listTab: 'today',
} as const;

describe('isDayKey — a real calendar day, in the date field’s own form', () => {
  it('accepts AAAA-MM-JJ days that exist', () => {
    for (const d of ['2026-10-25', '2028-02-29', '2026-12-31', '2026-01-01']) {
      expect(isDayKey(d), d).toBe(true);
    }
  });

  it('refuses impossible days and other shapes', () => {
    for (const d of [
      '2026-02-30',
      '2027-02-29',
      '2026-13-01',
      '2026-00-10',
      '2026-10-32',
      '2026-1-5',
      '26-10-25',
      'demain',
      '',
      '2026-10-25T09:00',
      ' 2026-10-25',
    ]) {
      expect(isDayKey(d), d).toBe(false);
    }
  });
});

describe('readAgenda — the address → what to show', () => {
  it('a bare address is today’s Journée', () => {
    expect(readAgenda('', TODAY)).toEqual(DEFAULTS);
  });

  it('?jour= opens the Journée on that day', () => {
    expect(readAgenda('?jour=2026-10-25', TODAY)).toEqual({
      ...DEFAULTS,
      journalDate: '2026-10-25',
    });
  });

  it('?vue=calendrier&jour= picks that day in the Calendrier (the Journée keeps today)', () => {
    expect(readAgenda('?vue=calendrier&jour=2026-10-25', TODAY)).toEqual({
      ...DEFAULTS,
      view: 'calendar',
      selected: '2026-10-25',
    });
  });

  it('?vue=liste&filtre= opens that tab of the Liste', () => {
    for (const [slug, tab] of [
      ['aujourdhui', 'today'],
      ['a-venir', 'upcoming'],
      ['en-attente', 'pending'],
      ['tous', 'all'],
    ] as const) {
      expect(readAgenda(`?vue=liste&filtre=${slug}`, TODAY), slug).toEqual({
        ...DEFAULTS,
        view: 'list',
        listTab: tab,
      });
    }
  });

  it('reads with or without the leading « ? », in any order', () => {
    expect(readAgenda('jour=2026-10-25&vue=calendrier', TODAY)).toEqual(
      readAgenda('?vue=calendrier&jour=2026-10-25', TODAY),
    );
  });

  it('a wrong address breaks nothing: each bad value is its default', () => {
    expect(readAgenda('?jour=2026-02-30', TODAY)).toEqual(DEFAULTS);
    expect(readAgenda('?jour=demain', TODAY)).toEqual(DEFAULTS);
    expect(readAgenda('?vue=semaine&jour=2026-10-25', TODAY)).toEqual({
      ...DEFAULTS,
      journalDate: '2026-10-25',
    });
    expect(readAgenda('?vue=liste&filtre=x', TODAY)).toEqual({
      ...DEFAULTS,
      view: 'list',
    });
  });

  it('a value meant for another view is not applied to this one', () => {
    // `filtre` is the Liste's; `jour` is the Journée's or the Calendrier's.
    expect(readAgenda('?filtre=tous', TODAY)).toEqual(DEFAULTS);
    expect(readAgenda('?vue=liste&jour=2026-10-25', TODAY)).toEqual({
      ...DEFAULTS,
      view: 'list',
    });
  });
});

describe('agendaQuery — what to show → the address', () => {
  it('the defaults are never written: today’s Journée is the bare address', () => {
    expect(agendaQuery(DEFAULTS, TODAY)).toBe('');
  });

  it('the spec’s table, row by row (§2.1)', () => {
    expect(agendaQuery({ ...DEFAULTS, journalDate: '2026-10-25' }, TODAY)).toBe(
      '?jour=2026-10-25',
    );
    expect(agendaQuery({ ...DEFAULTS, view: 'calendar' }, TODAY)).toBe(
      '?vue=calendrier',
    );
    expect(
      agendaQuery({ ...DEFAULTS, view: 'calendar', selected: '2026-10-25' }, TODAY),
    ).toBe('?vue=calendrier&jour=2026-10-25');
    expect(agendaQuery({ ...DEFAULTS, view: 'list' }, TODAY)).toBe('?vue=liste');
    expect(
      agendaQuery({ ...DEFAULTS, view: 'list', listTab: 'pending' }, TODAY),
    ).toBe('?vue=liste&filtre=en-attente');
  });

  it('only the shown view’s state is written', () => {
    // On the Liste, the Journée's day is not part of what the salon sees.
    expect(
      agendaQuery(
        { view: 'list', journalDate: '2026-10-25', selected: '2026-11-02', listTab: 'all' },
        TODAY,
      ),
    ).toBe('?vue=liste&filtre=tous');
  });

  it('round trip: what is written reads back as the same view', () => {
    const states = [
      { ...DEFAULTS, journalDate: '2026-10-25' },
      { ...DEFAULTS, view: 'calendar' as const, selected: '2026-11-02' },
      { ...DEFAULTS, view: 'list' as const, listTab: 'upcoming' as const },
    ];
    for (const s of states) {
      expect(readAgenda(agendaQuery(s, TODAY), TODAY)).toEqual(s);
    }
  });
});

describe('agendaParams — what the booking page hands back to « ← Rendez-vous »', () => {
  it('keeps the agenda’s own valid parameters', () => {
    expect(agendaParams('?jour=2026-10-25')).toBe('?jour=2026-10-25');
    expect(agendaParams('?vue=liste&filtre=tous')).toBe('?vue=liste&filtre=tous');
    expect(agendaParams('?vue=calendrier&jour=2026-10-25')).toBe(
      '?vue=calendrier&jour=2026-10-25',
    );
  });

  it('drops everything else — other parameters, bad values', () => {
    expect(agendaParams('')).toBe('');
    expect(agendaParams('?salon=p9')).toBe('');
    expect(agendaParams('?jour=2026-10-25&salon=p9&next=https://evil.test')).toBe(
      '?jour=2026-10-25',
    );
    expect(agendaParams('?jour=nope&vue=liste&filtre=tous')).toBe(
      '?vue=liste&filtre=tous',
    );
    expect(agendaParams('?vue=semaine&filtre=x')).toBe('');
  });

  it('a name every object has is not a word of the address', () => {
    // `'toString' in {}` is true: a lookup table read with `in` or `[]` would
    // take these for valid values.
    expect(agendaParams('?vue=toString&filtre=constructor')).toBe('');
    expect(readAgenda('?vue=toString&filtre=__proto__', TODAY)).toEqual(DEFAULTS);
    expect(readAgenda('?vue=liste&filtre=hasOwnProperty', TODAY)).toEqual({
      ...DEFAULTS,
      view: 'list',
    });
  });
});

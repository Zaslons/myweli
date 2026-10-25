import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

import { calendarTitle } from '../lib/account/calendar';
import { joinedSalonMessage, revokedAccessMessage, teamErrorMessage } from '../lib/pro/team';
import {
  UNNAMED_OWN_SALON,
  UNNAMED_SALON,
  salonNameOr,
  staffPlanningTitle,
} from '../lib/salon-name';

/// docs/design/hygiene-batch9.md §2.9 (B9.10) — a salon with no name has one
/// set of words, the app's (`mobile/lib/core/constants/unnamed_salon.dart`):
/// « Salon » as a title, « le salon » in a client's sentence, « votre salon »
/// in the Pro session's. The web had « Salon », « ce salon », « MyWeli »,
/// and an empty string that printed « — votre planning » with nothing before.

describe('salonNameOr', () => {
  it('a name is the name', () => {
    expect(salonNameOr('Salon Awa', UNNAMED_SALON)).toBe('Salon Awa');
  });
  it('null, undefined, empty or blank is the unnamed word', () => {
    for (const n of [null, undefined, '', '   ']) {
      expect(salonNameOr(n, UNNAMED_SALON)).toBe('Salon');
    }
  });
});

describe('the words, where they are said', () => {
  const appt = (providerName: string | null | undefined) =>
    ({
      id: 'a1',
      appointmentDate: '2026-11-02T10:00:00Z',
      providerName,
    }) as unknown as Parameters<typeof calendarTitle>[0];

  it('the calendar event: « Rendez-vous — Salon », as in the app — not « MyWeli »', () => {
    expect(calendarTitle(appt(null))).toBe('Rendez-vous — Salon');
    expect(calendarTitle(appt(''))).toBe('Rendez-vous — Salon');
    expect(calendarTitle(appt('Salon Awa'))).toBe('Rendez-vous — Salon Awa');
  });

  it('the Collaborateur\'s title: « Votre planning » alone, never « — votre planning »', () => {
    expect(staffPlanningTitle('')).toBe('Votre planning');
    expect(staffPlanningTitle(undefined)).toBe('Votre planning');
    expect(staffPlanningTitle('Salon Awa')).toBe('Salon Awa — votre planning');
  });

  it('a joined salon with no name: « Vous avez rejoint le salon »', () => {
    expect(joinedSalonMessage('')).toBe('Vous avez rejoint le salon');
    expect(joinedSalonMessage('Salon Awa')).toBe('Vous avez rejoint Salon Awa');
  });

  it('a lost salon with no name: the one sentence for a withdrawn access', () => {
    expect(revokedAccessMessage('')).toBe(teamErrorMessage('not_a_member'));
    expect(revokedAccessMessage('Salon Awa')).toBe('Votre accès à Salon Awa a été retiré.');
  });

  it('the Pro session\'s own salon, in a sentence: « votre salon »', () => {
    expect(UNNAMED_OWN_SALON).toBe('votre salon');
  });
});

/// The pin: the words live in `lib/salon-name.ts`. « Salon » is also a label
/// (a recap row, a column), so it counts only as a fallback — after `??`,
/// `||` or a ternary; « MyWeli » likewise (it is the brand everywhere else).
/// « ce salon » and « votre salon » as a whole literal are never labels.
describe('no page spells an unnamed salon itself', () => {
  const ROOT = join(__dirname, '..');
  function sources(dir: string): string[] {
    const out: string[] = [];
    for (const name of readdirSync(dir)) {
      const p = join(dir, name);
      if (statSync(p).isDirectory()) out.push(...sources(p));
      else if (/\.(ts|tsx)$/.test(name)) out.push(p);
    }
    return out;
  }

  it('finds no fallback literal outside lib/salon-name.ts', () => {
    const files = ['app', 'components', 'lib']
      .flatMap((d) => sources(join(ROOT, d)))
      .filter((f) => !f.endsWith(join('lib', 'salon-name.ts')));
    expect(files.length).toBeGreaterThan(100);
    const fallback =
      /['"`](ce salon|votre salon|le salon)['"`]|(\?\?|\|\||\?[^:?]*:)\s*['"`](Salon|MyWeli)['"`]/;
    const hits = files.flatMap((f) =>
      readFileSync(f, 'utf8')
        .split('\n')
        .map((line, i) => ({ line, i }))
        .filter(({ line }) => !line.trimStart().startsWith('//') && fallback.test(line))
        .map(({ line, i }) => `${f}:${i + 1}: ${line.trim()}`),
    );
    expect(hits).toEqual([]);
  });
});

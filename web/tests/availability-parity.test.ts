import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { CRENEAUX_COPY, SCHEDULE_PRESETS } from '../lib/pro/availability';

/// Identical French on both surfaces is the PRODUCT RULE for the hours
/// models and the créneaux line (availability-presets.md §2) — and a rule
/// that lives in two hand-written constant lists is drift waiting to happen,
/// which is exactly what `dart-tokens.mjs` exists to catch for the theme.
/// Same posture here, lighter mechanism: read the mobile source and assert
/// every label and the copy sentence appear verbatim.
const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const DART_PRESETS = readFileSync(
  join(REPO_ROOT, 'mobile/lib/core/constants/booking_horizons.dart'),
  'utf-8',
);

/// Dart splits long string literals into adjacent parts
/// (`'…à partir de '\n    'ces horaires…'`); joining the pairs restores the
/// sentence so a verbatim `contains` can see it.
const dartJoined = DART_PRESETS.replace(/'\s*\n\s*'/g, '');

describe('hours models + créneaux line — app/web parity', () => {
  it('every web label exists verbatim in the mobile presets', () => {
    for (const p of SCHEDULE_PRESETS) {
      expect(dartJoined, p.label).toContain(`'${p.label}'`);
    }
  });

  it('mobile has no label the web lacks (same count)', () => {
    const dartLabels = [...dartJoined.matchAll(/label: '([^']+)'/g)].map(
      (m) => m[1],
    );
    expect(dartLabels.sort()).toEqual(
      SCHEDULE_PRESETS.map((p) => p.label).sort(),
    );
  });

  it('the créneaux sentence is the same French, character for character', () => {
    expect(dartJoined).toContain(CRENEAUX_COPY);
  });

  it('the web hours mirror the mobile hours per label', () => {
    // `9h–18h` in a label promises 09:00–18:00 in the rows — on BOTH
    // platforms. Derive hours from each web preset's own label and check
    // them against its start/end, then check the dart side declares the
    // same startHour/endHour beside the same label.
    for (const p of SCHEDULE_PRESETS) {
      const m = /(\d+)h–(\d+)h/.exec(p.label);
      expect(m, p.label).not.toBeNull();
      const [, sh, eh] = m as RegExpExecArray;
      expect(p.start).toBe(`${sh.padStart(2, '0')}:00`);
      expect(p.end).toBe(`${eh.padStart(2, '0')}:00`);
      const block = dartJoined.slice(dartJoined.indexOf(`'${p.label}'`));
      expect(block).toContain(`startHour: ${sh}`);
      expect(block).toContain(`endHour: ${eh}`);
    }
  });
});

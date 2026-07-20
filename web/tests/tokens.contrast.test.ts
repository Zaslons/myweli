import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { colors } from '../styles/tokens';
import {
  FLOOR_NON_TEXT,
  FLOOR_TEXT,
  contrastRatio,
  ratioLabel,
} from './support/wcag';

/// The web design system's colour rules, EXECUTABLE (docs/design/SYSTEM.md §3,
/// WEB-SYSTEM §1/§14) — the TS twin of mobile's design_contrast_test.dart, using
/// the same wcag math so the two surfaces can't disagree about what passes.
///
/// If this went red: you didn't break a test, you broke a contrast floor. The
/// message carries the measured ratio.

// The three surfaces a token has to survive, worst → best. A token clears its
// floor on `background` (the worst case) to be legal anywhere.
const surfaces: Record<string, string> = {
  // The review disproved the old "background is the worst case" premise:
  // surfaceVariant (#F5F5F5) is DARKER than background (#F6F7F9), so it is
  // the true worst case for dark-on-light text — and it was asserted nowhere.
  surfaceVariant: colors.surfaceVariant,
  background: colors.background,
  surface: colors.surface,
  card: colors.secondary,
};

/// B3: every colors key must be asserted SOMEWHERE in this file. The coverage
/// ledger is STATIC (FLOOR_ROWS + WHITE_ON + the negative pins +
/// ASSERTED_ELSEWHERE) and the test bodies are GENERATED from it — the review
/// proved the first version's runtime-Set variant went vacuous under `-t`
/// filtering and test reordering; a declared table cannot.
type FloorRow = {
  key: keyof typeof colors;
  floor: number;
  note?: string;
  /** Scope to a surface subset — ONLY with a register entry explaining why. */
  on?: string[];
};

const FLOOR_ROWS: FloorRow[] = [
  // text — WCAG 1.4.3, 4.5:1
  { key: 'textPrimary', floor: FLOOR_TEXT, note: 'the ink' },
  { key: 'textSecondary', floor: FLOOR_TEXT },
  { key: 'textTertiary', floor: FLOOR_TEXT, note: 'the lightest legal text; nothing goes below it' },
  // No WCAG floor; ours: it must still read as *a disabled thing*. The old
  // #C0C0C0 was 1.70:1 — effectively nothing.
  { key: 'textDisabled', floor: 2.0, note: 'exempt, but legible-inert — not blank' },
  // non-text — WCAG 1.4.11, 3:1
  { key: 'borderStrong', floor: FLOOR_NON_TEXT, note: 'the boundary of an interactive control' },
  // 19.59:1 — trivially passes. The row exists because the TOKEN once didn't:
  // borderFocus was promised by WEB-SYSTEM §1/§5 from B1 and only landed in
  // B4 (the sixth mirror drift). With the row here, deleting the token goes red.
  { key: 'borderFocus', floor: FLOOR_NON_TEXT, note: 'the focus ring (§5)' },
  // gold measures 2.98:1 on surfaceVariant — BELOW the floor by 0.02. Found
  // the moment the review's worst-case surface landed; mobile mirrors the
  // same value and never measured it either. B3 cannot re-pick a mirrored
  // brand value, so the row is scoped and the gap is REGISTERED (§15 row 23):
  // the fix is a cross-surface token change (mobile first, the gate carries
  // it over).
  { key: 'gold', floor: FLOOR_NON_TEXT, note: 'gold-as-state (the owner chip)', on: ['background', 'surface', 'card'] },
  { key: 'favorite', floor: FLOOR_NON_TEXT, note: 'the heart glyph' },
  { key: 'categorySpa', floor: FLOOR_TEXT },
  { key: 'categoryBarber', floor: FLOOR_TEXT },
  { key: 'categorySalon', floor: FLOOR_TEXT },
  // semantic — every status colour legible as text
  { key: 'success', floor: FLOOR_TEXT },
  { key: 'successLight', floor: FLOOR_TEXT },
  { key: 'error', floor: FLOOR_TEXT },
  { key: 'errorLight', floor: FLOOR_TEXT },
  { key: 'warning', floor: FLOOR_TEXT },
  { key: 'info', floor: FLOOR_TEXT },
  { key: 'infoLight', floor: FLOOR_TEXT },
];

/** White label text sits on these fills (buttons, status chips). */
const WHITE_ON: (keyof typeof colors)[] = ['success', 'error', 'primaryHover'];

/** Deliberately BELOW the floor — decoration/tints only, pinned negatively. */
const NEGATIVE_PINS: (keyof typeof colors)[] = ['starRating', 'warningLight'];

function expectFloor(name: string, c: string, floor: number, on?: string[]) {
  for (const [surfaceName, bg] of Object.entries(surfaces)) {
    if (on && !on.includes(surfaceName)) continue;
    const ratio = contrastRatio(c, bg);
    expect(
      ratio,
      `${name} on ${surfaceName} is ${ratioLabel(ratio)}:1 — below the ${floor.toFixed(1)}:1 floor`,
    ).toBeGreaterThanOrEqual(floor);
  }
}

describe('floors — WCAG 1.4.3 text (4.5) / 1.4.11 non-text (3), from the ledger', () => {
  for (const row of FLOOR_ROWS) {
    it(`${row.key}${row.note ? ` — ${row.note}` : ''} ≥ ${row.floor.toFixed(1)}:1`, () =>
      expectFloor(row.key, colors[row.key], row.floor, row.on));
  }
});

describe('white-on-fill (buttons, status chips)', () => {
  for (const name of WHITE_ON) {
    it(`white on ${name}`, () => {
      const ratio = contrastRatio(colors.secondary, colors[name]);
      expect(ratio, `white on ${name} is ${ratioLabel(ratio)}:1`).toBeGreaterThanOrEqual(
        FLOOR_TEXT,
      );
    });
  }
});

describe('the negative pins — deliberately BELOW the floor, decoration/tints only', () => {
  it('warningLight is a TINT, never a foreground (the mobile pin, mirrored)', () => {
    // Mobile's design_contrast_test asserts the same: #FFB800 works only as a
    // fill under ink — below 3:1 on every surface as a foreground.
    for (const surface of Object.values(surfaces)) {
      expect(contrastRatio(colors.warningLight, surface)).toBeLessThan(FLOOR_NON_TEXT);
    }
  });
});

describe('the two blacks (SYSTEM.md §1)', () => {
  it('primary is pinned to pure black — it is the brand', () => {
    expect(colors.primary).toBe('#000000');
    expect(contrastRatio(colors.secondary, colors.primary)).toBeCloseTo(21, 1);
  });
  it('the ink is NOT the brand black — the split may not silently collapse', () => {
    expect(
      colors.textPrimary,
      'textPrimary is back to the brand black; text is never `primary` (SYSTEM.md §1)',
    ).not.toBe(colors.primary);
    expect(
      contrastRatio(colors.textPrimary, colors.background),
    ).toBeGreaterThanOrEqual(7.0);
  });
  it('the border roles are ordered: divider < border < borderStrong', () => {
    const r = (c: string) => contrastRatio(c, colors.background);
    expect(r(colors.divider)).toBeLessThan(r(colors.border));
    expect(r(colors.border)).toBeLessThan(r(colors.borderStrong));
  });
});

describe('every colour is asserted (B3 — the completeness gate)', () => {
  // Keys whose assertions have a different shape than a floor row: the
  // surfaces (they are the BACKGROUND side of every expectFloor ratio —
  // surfaceVariant included since the review proved it is the true worst
  // case), the two-blacks identity pins, and the ordering trio.
  const ASSERTED_ELSEWHERE = [
    'primary', // two-blacks pin + 21:1 white-on-primary
    'secondary', // IS the card surface (and the white of white-on-fill)
    'secondaryVariant', // = surfaceVariant's hex — a surface, not a foreground
    'background', // a surface (an expectFloor denominator)
    'surface', // a surface
    'surfaceVariant', // a surface — IN the surfaces record since the review
    'divider', // decorative by design — the ordering test places it
    'border', // container hairline — the ordering test places it
  ];
  it('no colors key escapes this file (a STATIC ledger — filter/order-proof)', () => {
    const covered = new Set<string>([
      ...FLOOR_ROWS.map((r) => r.key),
      ...WHITE_ON,
      ...NEGATIVE_PINS,
      ...ASSERTED_ELSEWHERE,
    ]);
    const missing = Object.keys(colors).filter((k) => !covered.has(k));
    expect(
      missing,
      'colors keys with NO contrast assertion — add a FLOOR_ROWS entry, a ' +
        'negative pin, or a documented ASSERTED_ELSEWHERE entry',
    ).toEqual([]);
  });
});

describe('starRating is decoration, not a foreground (§3.5)', () => {
  it('is below the non-text floor — so it can only ever fill a glyph, and the '
    + 'numeral carries the meaning; gold-as-state uses `gold`', () => {
    expect(
      contrastRatio(colors.starRating, colors.background),
    ).toBeLessThan(FLOOR_NON_TEXT);
    expect(
      contrastRatio(colors.gold, colors.background),
    ).toBeGreaterThanOrEqual(FLOOR_NON_TEXT);
  });
});

// ---------------------------------------------------------------------------
// Grep-pins. A value can be asserted; a USAGE has to be searched — and these two
// are exactly the ones B1 fixed, so they're exactly the ones that creep back.
// The vitest analogue of the mobile design_contrast_test.dart pins.
// ---------------------------------------------------------------------------
function classNamesUnder(dir: string): { file: string; text: string }[] {
  const out: { file: string; text: string }[] = [];
  const walk = (d: string) => {
    for (const entry of readdirSync(d)) {
      const p = join(d, entry);
      if (statSync(p).isDirectory()) walk(p);
      else if (/\.(tsx?|css)$/.test(entry)) out.push({ file: p, text: readFileSync(p, 'utf8') });
    }
  };
  walk(dir);
  return out;
}

describe('usage pins', () => {
  const files = [...classNamesUnder('app'), ...classNamesUnder('components')];

  it('the ink never fills or strokes — no bg-textPrimary / border-textPrimary (§1)', () => {
    const offenders = files
      .filter((f) => /\b(bg|border)-textPrimary\b/.test(f.text))
      .map((f) => f.file);
    expect(
      offenders,
      `textPrimary is INK; use \`primary\` for a fill or stroke:\n${offenders.join('\n')}`,
    ).toEqual([]);
  });

  it('starRating never colours a fill or a border — that is gold-as-state (§3.5)', () => {
    // Defends the B1 gold-drift fix: the moment someone reintroduces a
    // bg-starRating/border-starRating (like TeamRoleChip did), this fails.
    const offenders = files
      .filter((f) => /\b(bg|border)-starRating\b/.test(f.text))
      .map((f) => f.file);
    expect(
      offenders,
      `starRating is the fill of a star GLYPH (1.62:1). Gold-as-state uses \`gold\`:\n${offenders.join('\n')}`,
    ).toEqual([]);
  });
});

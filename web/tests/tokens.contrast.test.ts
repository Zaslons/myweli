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
  background: colors.background,
  surface: colors.surface,
  card: colors.secondary,
};

function expectFloor(name: string, c: string, floor: number) {
  for (const [surfaceName, bg] of Object.entries(surfaces)) {
    const ratio = contrastRatio(c, bg);
    expect(
      ratio,
      `${name} on ${surfaceName} is ${ratioLabel(ratio)}:1 — below the ${floor.toFixed(1)}:1 floor`,
    ).toBeGreaterThanOrEqual(floor);
  }
}

describe('text — WCAG 1.4.3, 4.5:1', () => {
  it('textPrimary (the ink)', () =>
    expectFloor('textPrimary', colors.textPrimary, FLOOR_TEXT));
  it('textSecondary', () =>
    expectFloor('textSecondary', colors.textSecondary, FLOOR_TEXT));
  it('textTertiary — the lightest legal text; nothing goes below it', () =>
    expectFloor('textTertiary', colors.textTertiary, FLOOR_TEXT));
  it('textDisabled is exempt, but legible-inert — not blank', () =>
    // No WCAG floor; ours: it must still read as *a disabled thing*. The old
    // #C0C0C0 was 1.70:1 — effectively nothing.
    expectFloor('textDisabled', colors.textDisabled, 2.0));
});

describe('non-text — WCAG 1.4.11, 3:1', () => {
  it('borderStrong — the boundary of an interactive control', () =>
    expectFloor('borderStrong', colors.borderStrong, FLOOR_NON_TEXT));
  // 19.59:1 — trivially passes. The row exists because the TOKEN once didn't:
  // borderFocus was promised by WEB-SYSTEM §1/§5 from B1 and only landed in B4
  // (the sixth mirror drift). With the row here, deleting the token goes red.
  it('borderFocus — the focus ring (§5)', () =>
    expectFloor('borderFocus', colors.borderFocus, FLOOR_NON_TEXT));
  it('gold — gold-as-state (the owner chip)', () =>
    expectFloor('gold', colors.gold, FLOOR_NON_TEXT));
  it('favorite — the heart glyph', () =>
    expectFloor('favorite', colors.favorite, FLOOR_NON_TEXT));
  it('the category accents stay legible', () => {
    expectFloor('categorySpa', colors.categorySpa, FLOOR_TEXT);
    expectFloor('categoryBarber', colors.categoryBarber, FLOOR_TEXT);
    expectFloor('categorySalon', colors.categorySalon, FLOOR_TEXT);
  });
});

describe('semantic', () => {
  it('every status colour is legible as text', () => {
    expectFloor('success', colors.success, FLOOR_TEXT);
    expectFloor('successLight', colors.successLight, FLOOR_TEXT);
    expectFloor('error', colors.error, FLOOR_TEXT);
    expectFloor('errorLight', colors.errorLight, FLOOR_TEXT);
    expectFloor('warning', colors.warning, FLOOR_TEXT);
    expectFloor('info', colors.info, FLOOR_TEXT);
  });
  it('white on the filled status surfaces', () => {
    for (const [name, fill] of [
      ['success', colors.success],
      ['error', colors.error],
    ] as const) {
      const ratio = contrastRatio(colors.secondary, fill);
      expect(ratio, `white on ${name} is ${ratioLabel(ratio)}:1`).toBeGreaterThanOrEqual(
        FLOOR_TEXT,
      );
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

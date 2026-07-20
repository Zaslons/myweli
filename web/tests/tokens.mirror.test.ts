import { describe, expect, it } from 'vitest';
import {
  WEB_ONLY,
  expectedWebTokens,
} from '../scripts/dart-tokens.mjs';
import { colors, icon, motion, radius, spacing, type, zIndex } from '../styles/tokens';

/// B3 — the mirror gate (WEB-SYSTEM §15 row 19).
///
/// tokens.ts is a hand-mirror of mobile/lib/core/theme/, and the hand-mirror
/// drifted SIX times (gold dropped → an invisible chip shipped; sm/xxxl
/// dropped; tracking nearly dropped; warningLight/infoLight mobile-only for
/// five slices; borderFocus missing while §5's own snippet consumed it). Every
/// one sailed past typecheck, lint, and every test — the mirror had no gate.
///
/// This is the gate. It parses the Dart sources (and the two doc tables that
/// are the truth for the web-only families) ON EVERY TEST RUN and fails on any
/// mismatch, either direction. Healing is `npm run gen:tokens` — a printer,
/// not a writer: tokens.ts stays hand-owned because its comments carry the
/// drift histories, and deleting the project's memory to save a paste is a
/// bad trade.

const expected = expectedWebTokens();

/** Missing/extra key report with the actionable message the plan demands. */
function keyDiff(
  family: string,
  mobile: Record<string, unknown>,
  web: Record<string, unknown>,
  webOnly: string[] = [],
) {
  const missing = Object.keys(mobile)
    .filter((k) => !(k in web))
    .map((k) => `${family}.${k} = ${JSON.stringify(mobile[k])} — MISSING on web. Run \`npm run gen:tokens\`.`);
  const extra = Object.keys(web)
    .filter((k) => !(k in mobile) && !webOnly.includes(k))
    .map((k) => `${family}.${k} — web-only but NOT declared in WEB_ONLY (a web-invented token is a mirror divergence too).`);
  return [...missing, ...extra];
}

describe('the token mirror gate (B3, row 19)', () => {
  it('parses every declaration it can see — none skipped silently', () => {
    for (const check of expected.parseChecks) {
      expect(
        check.parsed,
        `${check.file}: ${check.raw} idiom declarations but only ${check.parsed} parsed — ` +
          `an unparseable declaration would otherwise vanish from the mirror silently ` +
          `(the mechanism of drifts #1/#2/#6). Fix the declaration or teach scripts/dart-tokens.mjs the new idiom.`,
      ).toBe(check.raw);
    }
  });

  it('every AppTheme scalar belongs to a family', () => {
    expect(
      expected.unclaimedDoubles,
      'AppTheme constants no family claims — add them to SPACING_KEYS/RADIUS_KEYS/ICON_KEYS ' +
        'in scripts/dart-tokens.mjs (or they can never reach the web)',
    ).toEqual([]);
  });

  it('colors mirror AppColors exactly', () => {
    expect(keyDiff('colors', expected.colors, colors)).toEqual([]);
    expect(colors).toEqual(expected.colors);
  });

  it('spacing mirrors AppTheme.spacing* exactly (+ the declared web-only 0)', () => {
    expect(keyDiff('spacing', expected.spacing, spacing, WEB_ONLY.spacing)).toEqual([]);
    const { 0: zero, ...mirrored } = spacing as Record<string, string>;
    expect(zero, "spacing '0' is the declared web-only key (inset-0/pb-0)").toBe('0px');
    expect(mirrored).toEqual(expected.spacing);
  });

  it('radius mirrors AppTheme.radius* exactly', () => {
    expect(keyDiff('radius', expected.radius, radius)).toEqual([]);
    expect(radius).toEqual(expected.radius);
  });

  it('icon mirrors AppTheme.icon* exactly — bare sizes, no lineHeight', () => {
    expect(keyDiff('icon', expected.icon, icon)).toEqual([]);
    expect(icon).toEqual(expected.icon);
  });

  it('type mirrors AppTextStyles exactly — weight stripped, height resolved to px', () => {
    expect(keyDiff('type', expected.type, type)).toEqual([]);
    expect(type).toEqual(expected.type);
  });

  it('motion matches SYSTEM.md §9 (the doc IS the source — no Dart upstream)', () => {
    const { DEFAULT, ...rest } = motion as Record<string, string>;
    expect(keyDiff('motion', expected.motion, rest, [])).toEqual([]);
    expect(rest).toEqual(expected.motion);
    expect(
      DEFAULT,
      'motion.DEFAULT must equal base — every bare `transition` reads it (dropping it makes them instant, silently)',
    ).toBe(expected.motion.base);
  });

  it('zIndex matches WEB-SYSTEM.md §9 (+ the declared auto escape)', () => {
    const { auto, ...rest } = zIndex as Record<string, string>;
    expect(keyDiff('zIndex', expected.zIndex, rest, [])).toEqual([]);
    expect(rest).toEqual(expected.zIndex);
    expect(auto, "zIndex.auto is the flex-item escape — WEB-SYSTEM §9's own table documents it").toBe('auto');
  });
});

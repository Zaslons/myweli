import { describe, expect, it } from 'vitest';
import {
  ICON_KEYS,
  RADIUS_KEYS,
  SPACING_KEYS,
  WEB_ONLY,
  expectedWebTokens,
} from '../scripts/dart-tokens.mjs';
import { colors, icon, motion, radius, screens, spacing, type, zIndex } from '../styles/tokens';

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
///
/// The adversarial review then defeated the first version five ways — all
/// fixed and pinned by scripts/dart-tokens.review.test.ts: comments parsed as
/// code (a commented-out declaration kept a removed token alive; a stale
/// field comment SHADOWED the live value) → comments are stripped first;
/// `static final` / type-inferred declarations invisible to both the parser
/// AND the old opener-count self-check → the candidate check (every
/// `static const|final … =` must parse); doc-table rows with format drift
/// (`600 ms`, a bolded cell) silently vanishing → per-table row-count checks;
/// a NEW theme file (motion.dart someday) unread → the directory manifest
/// below.

const expected = expectedWebTokens();

/** Web key → its mobile constant name, so a failure names BOTH sides. */
function reverse(keyMap: Record<string, string>) {
  return Object.fromEntries(Object.entries(keyMap).map(([dart, web]) => [web, dart]));
}
const MOBILE_NAME: Record<string, Record<string, string>> = {
  spacing: reverse(SPACING_KEYS),
  radius: reverse(RADIUS_KEYS),
  icon: reverse(ICON_KEYS),
};

function keyDiff(
  family: string,
  mobile: Record<string, unknown>,
  web: Record<string, unknown>,
  webOnly: string[] = [],
) {
  const dartName = (k: string) => MOBILE_NAME[family]?.[k] ?? k;
  const missing = Object.keys(mobile)
    .filter((k) => !(k in web))
    .map(
      (k) =>
        `mobile ${dartName(k)} = ${JSON.stringify(mobile[k])} → web ${family}.${k} — MISSING on web. Run \`npm run gen:tokens\`.`,
    );
  const extra = Object.keys(web)
    .filter((k) => !(k in mobile) && !webOnly.includes(k))
    .map(
      (k) =>
        `${family}.${k} — web-only but NOT declared in WEB_ONLY (a web-invented token is a mirror divergence too).`,
    );
  return [...missing, ...extra];
}

/** The mirrored slice of a web export: everything not declared web-only. */
function mirroredPart(web: Record<string, string>, webOnly: string[]) {
  return Object.fromEntries(Object.entries(web).filter(([k]) => !webOnly.includes(k)));
}

describe('the token mirror gate (B3, row 19)', () => {
  it('the theme directory holds exactly the files this gate reads', () => {
    // A new theme file (a motion.dart when §9's Dart side lands, a dark
    // palette…) is a token source the parsers never open — force the
    // conscious decision instead of silently ignoring it.
    expect(expected.themeFiles).toEqual(expected.knownThemeFiles);
  });

  it('every candidate declaration parses — none skipped silently', () => {
    for (const check of expected.parseChecks) {
      const unparsed = check.candidates.filter((c: string) => !check.parsed.includes(c));
      expect(
        unparsed,
        `${check.file}: declarations no idiom parser understands — a \`static final\`, ` +
          `a type-inferred const, or a new shape. Teach scripts/dart-tokens.mjs the idiom ` +
          `(or the token silently never reaches the web — the mechanism of drifts #1/#2/#6).`,
      ).toEqual([]);
      // Both directions: a parser inventing tokens no candidate declares
      // would be just as wrong.
      const phantom = check.parsed.filter((p: string) => !check.candidates.includes(p));
      expect(phantom, `${check.file}: parsed names with no candidate declaration`).toEqual([]);
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

  it('spacing mirrors AppTheme.spacing* exactly (+ the declared web-only keys)', () => {
    expect(keyDiff('spacing', expected.spacing, spacing, WEB_ONLY.spacing)).toEqual([]);
    expect(mirroredPart(spacing, WEB_ONLY.spacing)).toEqual(expected.spacing);
    expect(
      (spacing as Record<string, string>)['0'],
      "spacing '0' is the declared web-only key (inset-0/pb-0 need it)",
    ).toBe('0px');
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
    expect(keyDiff('motion', expected.motion, motion, WEB_ONLY.motion)).toEqual([]);
    expect(mirroredPart(motion, WEB_ONLY.motion)).toEqual(expected.motion);
    expect(
      (motion as Record<string, string>).DEFAULT,
      'motion.DEFAULT must equal base — every bare `transition` reads it (dropping it makes them instant, silently)',
    ).toBe(expected.motion.base);
  });

  it('zIndex matches WEB-SYSTEM.md §9 (+ the declared auto escape)', () => {
    expect(keyDiff('zIndex', expected.zIndex, zIndex, WEB_ONLY.zIndex)).toEqual([]);
    expect(mirroredPart(zIndex, WEB_ONLY.zIndex)).toEqual(expected.zIndex);
    expect(
      (zIndex as Record<string, string>).auto,
      "zIndex.auto is the flex-item escape — WEB-SYSTEM §9's own table documents it",
    ).toBe('auto');
  });

  it("screens are Tailwind's stock five, pinned by VALUE", () => {
    // The closed theme freezes the KEYS; nothing froze the VALUES until the
    // review mutated one and every test stayed green. Deliberately Tailwind's
    // stock (SYSTEM §10 maps them onto the shared window classes) — a sixth
    // breakpoint or a moved value is a design-system change, not a tweak.
    expect(screens).toEqual({
      sm: '640px',
      md: '768px',
      lg: '1024px',
      xl: '1280px',
      '2xl': '1536px',
    });
  });
});

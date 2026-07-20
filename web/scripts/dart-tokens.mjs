// The Flutter→web token parser + mapping table (B3, WEB-SYSTEM §15 row 19).
//
// ONE module, TWO consumers: tests/tokens.mirror.test.ts (the blocking drift
// gate) and scripts/gen-tokens.mjs (the healing printer). Plain ESM so both
// vitest and bare `node` can import it — the web CI job has Node and a
// full-repo checkout but NO Flutter, so the Dart SOURCE TEXT is the
// machine-readable truth (mobile exports no JSON, and a mobile-side emitter
// would just be a second mirror to drift).
//
// The mapping table below IS the doctrine: every deliberate divergence between
// the Flutter theme and web/styles/tokens.ts is encoded here, explicitly, with
// its reason. Anything not encoded is drift, and the gate fails on it.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const WEB_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const REPO_ROOT = join(WEB_ROOT, '..');

export const SOURCES = {
  colors: join(REPO_ROOT, 'mobile/lib/core/theme/colors.dart'),
  appTheme: join(REPO_ROOT, 'mobile/lib/core/theme/app_theme.dart'),
  textStyles: join(REPO_ROOT, 'mobile/lib/core/theme/text_styles.dart'),
  systemDoc: join(REPO_ROOT, 'docs/design/SYSTEM.md'),
  webSystemDoc: join(REPO_ROOT, 'docs/design/WEB-SYSTEM.md'),
};

// ---------------------------------------------------------------------------
// Parsers — one per declaration idiom. Each returns { parsed, rawCount }:
// rawCount is the number of idiom OPENERS in the file, and the gate asserts
// parsed-count === rawCount. That self-check is what closes the silent-parse
// hole: a future declaration that deviates from the idiom (a computed color, a
// reformatted TextStyle) fails LOUD instead of quietly vanishing from the
// mirror — the exact mechanism of historical drifts #1/#2/#6 was "the mirror
// just didn't have it, and nothing could see that".
// ---------------------------------------------------------------------------

/** `static const Color name = Color(0xFFRRGGBB);` → { name: '#RRGGBB' } */
export function parseColors(src) {
  const parsed = {};
  for (const m of src.matchAll(
    /static const Color (\w+) =\s*Color\(0xFF([0-9A-Fa-f]{6})\);/g,
  )) {
    parsed[m[1]] = `#${m[2].toUpperCase()}`;
  }
  const rawCount = (src.match(/static const Color\b/g) ?? []).length;
  return { parsed, rawCount };
}

/** `static const double name = N;` → { name: number } */
export function parseDoubles(src) {
  const parsed = {};
  for (const m of src.matchAll(/static const double (\w+) =\s*([\d.]+);/g)) {
    parsed[m[1]] = Number(m[2]);
  }
  const rawCount = (src.match(/static const double\b/g) ?? []).length;
  return { parsed, rawCount };
}

/** `static const TextStyle name = TextStyle(...);` with the body parsed
 *  field-by-field (order-independent). `height` is a division EXPRESSION in
 *  the source (`64 / 57`) — evaluated here. `fontWeight` is captured so the
 *  self-check sees a complete parse, then DROPPED by the mapper (§3: weight is
 *  deliberately not in the web token). */
export function parseTextStyles(src) {
  const parsed = {};
  for (const m of src.matchAll(
    /static const TextStyle (\w+) =\s*TextStyle\(([^)]*)\);/g,
  )) {
    const [, name, body] = m;
    const fontSize = body.match(/fontSize:\s*([\d.]+)/);
    const height = body.match(/height:\s*([\d.]+)\s*\/\s*([\d.]+)/);
    const letterSpacing = body.match(/letterSpacing:\s*(-?[\d.]+)/);
    const fontWeight = body.match(/fontWeight:\s*FontWeight\.(\w+)/);
    if (!fontSize || !height || !letterSpacing || !fontWeight) {
      throw new Error(
        `text_styles.dart: "${name}" is missing a field the mirror needs ` +
          `(fontSize/height/letterSpacing/fontWeight) — got: ${body.trim()}`,
      );
    }
    parsed[name] = {
      fontSize: Number(fontSize[1]),
      lineHeight: Math.round(
        (Number(height[1]) / Number(height[2])) * Number(fontSize[1]),
      ),
      letterSpacing: Number(letterSpacing[1]),
      fontWeight: fontWeight[1], // parsed for completeness; the mapper drops it
    };
  }
  const rawCount = (src.match(/static const TextStyle\b/g) ?? []).length;
  return { parsed, rawCount };
}

/** Extract `token → number` pairs from a markdown table whose first column is
 *  a backticked token name and second column a `Nms`/`N` value. Scoped to the
 *  section between `heading` and the next `## `. */
export function parseMdTable(md, heading, tokenRe) {
  const start = md.indexOf(heading);
  if (start === -1) throw new Error(`doc section not found: ${heading}`);
  const end = md.indexOf('\n## ', start + heading.length);
  const section = md.slice(start, end === -1 ? undefined : end);
  const out = {};
  for (const m of section.matchAll(tokenRe)) out[m[1]] = Number(m[2]);
  if (Object.keys(out).length === 0) {
    throw new Error(`no token rows matched under ${heading}`);
  }
  return out;
}

// ---------------------------------------------------------------------------
// The mapping table — every deliberate divergence, named.
// ---------------------------------------------------------------------------

/** Mobile scalar name → web key. Split by family so a stray double can't leak
 *  into the wrong export. */
export const SPACING_KEYS = {
  spacingXS: 'xs',
  spacingS: 's',
  spacingSM: 'sm',
  spacingM: 'm',
  spacingL: 'l',
  spacingXL: 'xl',
  spacingXXL: 'xxl',
  spacingXXXL: 'xxxl',
};

export const RADIUS_KEYS = {
  radiusSmall: 'sm',
  radiusMedium: 'md',
  radiusLarge: 'lg',
  radiusXL: 'xl',
  radiusXXL: 'xxl',
  radiusPill: 'pill',
};

export const ICON_KEYS = {
  iconXS: 'iconXS',
  iconS: 'iconS',
  iconM: 'iconM',
  iconL: 'iconL',
  iconXL: 'iconXL',
};

/** Web-side keys with NO mobile source, each with its reason. The gate fails
 *  on any web key that is neither mirrored nor declared here. */
export const WEB_ONLY = {
  // Tailwind's `inset-0`/`pb-0` need the key; "0" is not a spacing VALUE.
  spacing: ['0'],
  // Every bare `transition`/`transition-colors` reads transitionDuration
  // .DEFAULT — dropping it makes them all instant, silently (= motion.base).
  motion: ['DEFAULT'],
  // The flex-item escape (WEB-SYSTEM §9's own table documents it).
  zIndex: ['auto'],
};

/** Build the expected web exports from the mobile sources + doc tables. */
export function expectedWebTokens() {
  const colorsSrc = readFileSync(SOURCES.colors, 'utf8');
  const themeSrc = readFileSync(SOURCES.appTheme, 'utf8');
  const stylesSrc = readFileSync(SOURCES.textStyles, 'utf8');

  const colors = parseColors(colorsSrc);
  const doubles = parseDoubles(themeSrc);
  const styles = parseTextStyles(stylesSrc);

  const pick = (keyMap, px = true) => {
    const out = {};
    for (const [dartName, webKey] of Object.entries(keyMap)) {
      if (dartName in doubles.parsed) {
        const n = doubles.parsed[dartName];
        out[webKey] = px ? `${n}px` : n;
      }
    }
    return out;
  };

  const type = {};
  for (const [name, s] of Object.entries(styles.parsed)) {
    // fontWeight DROPPED — §3's single deliberate mirror divergence.
    type[name] = [
      `${s.fontSize}px`,
      {
        lineHeight: `${s.lineHeight}px`,
        letterSpacing: `${s.letterSpacing}px`,
      },
    ];
  }

  // The doc-pinned web-only families (drift #6 was a doc↔code lie — the pin
  // cuts both ways: the doc table is the truth the code must match).
  const motionDoc = parseMdTable(
    readFileSync(SOURCES.systemDoc, 'utf8'),
    '## 9. Motion',
    /\|\s*`motion(\w+)`\s*\|\s*(\d+)ms\s*\|/g,
  );
  const motion = {};
  for (const [name, ms] of Object.entries(motionDoc)) {
    motion[name[0].toLowerCase() + name.slice(1)] = `${ms}ms`;
  }

  const zIndexDoc = parseMdTable(
    readFileSync(SOURCES.webSystemDoc, 'utf8'),
    '### z-index',
    /\|\s*`z-(\w+)`\s*\|\s*(\d+)\s*\|/g,
  );
  const zIndex = {};
  for (const [name, n] of Object.entries(zIndexDoc)) zIndex[name] = `${n}`;

  return {
    colors: colors.parsed,
    spacing: pick(SPACING_KEYS),
    radius: pick(RADIUS_KEYS),
    icon: pick(ICON_KEYS),
    type,
    motion,
    zIndex,
    // The self-check inputs, surfaced for the gate's assertions.
    parseChecks: [
      { file: 'colors.dart', raw: colors.rawCount, parsed: Object.keys(colors.parsed).length },
      { file: 'app_theme.dart', raw: doubles.rawCount, parsed: Object.keys(doubles.parsed).length },
      { file: 'text_styles.dart', raw: styles.rawCount, parsed: Object.keys(styles.parsed).length },
    ],
    // Scalars the double-parse found that no family claims — the gate asserts
    // this is empty so a NEW AppTheme constant can't fall between families.
    unclaimedDoubles: Object.keys(doubles.parsed).filter(
      (k) => !(k in SPACING_KEYS) && !(k in RADIUS_KEYS) && !(k in ICON_KEYS),
    ),
  };
}

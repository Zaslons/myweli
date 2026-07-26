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

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const WEB_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const REPO_ROOT = join(WEB_ROOT, '..');

export const SOURCES = {
  colors: join(REPO_ROOT, 'mobile/lib/core/theme/colors.dart'),
  appTheme: join(REPO_ROOT, 'mobile/lib/core/theme/app_theme.dart'),
  textStyles: join(REPO_ROOT, 'mobile/lib/core/theme/text_styles.dart'),
  motion: join(REPO_ROOT, 'mobile/lib/core/theme/motion.dart'),
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

/** Dart comments are NOT tokens. The review proved every parser hole below
 *  traced back to reading comments as code: a commented-out declaration kept a
 *  removed token alive; a stale `// letterSpacing: 0.15` SHADOWED the live
 *  field (first-match won); a stale declaration comment AFTER the live line
 *  OVERWROTE it (last-match won); a prose TODO mentioning the idiom turned the
 *  self-check permanently red. Strip `//` and `/* *​/` before any regex runs.
 *  (The `64 / 57` height expressions survive: `//` needs two ADJACENT
 *  slashes.) */
export function stripDartComments(src) {
  return src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}

/** Every `static const|final [Type] name = …` in the (comment-stripped)
 *  source — the CANDIDATE set. The gate asserts every candidate is parsed by
 *  an idiom parser: a `static final Color` (withValues() is not const-able) or
 *  a type-inferred `static const scrim = Color(…)` is a real token the narrow
 *  idioms would silently miss — the review landed both past the old
 *  opener-count self-check. Getters (`static X get name =>`) and methods
 *  don't match `=` and are skipped by construction. */
export function tokenCandidates(stripped) {
  return [...stripped.matchAll(
    /static\s+(?:const|final)\s+(?:[A-Za-z_][\w<>]*\s+)?(\w+)\s*=(?!=|>)/g,
  )].map((m) => m[1]);
}

/** `static const Color name = Color(0xFFRRGGBB);` → { name: '#RRGGBB' } */
export function parseColors(src) {
  const stripped = stripDartComments(src);
  const parsed = {};
  for (const m of stripped.matchAll(
    /static const Color (\w+) =\s*Color\(0xFF([0-9A-Fa-f]{6})\);/g,
  )) {
    parsed[m[1]] = `#${m[2].toUpperCase()}`;
  }
  return { parsed, candidates: tokenCandidates(stripped) };
}

/** `static const double name = N;` → { name: number } */
export function parseDoubles(src) {
  const stripped = stripDartComments(src);
  const parsed = {};
  for (const m of stripped.matchAll(/static const double (\w+) =\s*([\d.]+);/g)) {
    parsed[m[1]] = Number(m[2]);
  }
  return { parsed, candidates: tokenCandidates(stripped) };
}

/** `static const Duration name = Duration(milliseconds: N);` and
 *  `static const Curve name = Curves.x;` → the §9 motion family (A8).
 *
 *  Curves are parsed but NOT mirrored: `tokens.ts` says so at its motion
 *  export — Tailwind has no `easeOutCubic` equivalent, so the web takes
 *  durations and stops. They are parsed anyway because the candidate
 *  self-check demands it: an unparsed `static const Curve` would look exactly
 *  like a token the mirror had silently dropped. */
export function parseMotion(src) {
  const stripped = stripDartComments(src);
  const durations = {};
  for (const m of stripped.matchAll(
    /static const Duration (\w+) =\s*Duration\(milliseconds: (\d+)\);/g,
  )) {
    durations[m[1]] = Number(m[2]);
  }
  const curves = {};
  for (const m of stripped.matchAll(
    /static const Curve (\w+) =\s*Curves\.(\w+);/g,
  )) {
    curves[m[1]] = m[2];
  }
  return { durations, curves, candidates: tokenCandidates(stripped) };
}

/** `static const TextStyle name = TextStyle(...);` with the body parsed
 *  field-by-field (order-independent). `height` is a division EXPRESSION in
 *  the source (`64 / 57`) — evaluated here. `fontWeight` is captured so the
 *  self-check sees a complete parse, then DROPPED by the mapper (§3: weight is
 *  deliberately not in the web token). */
export function parseTextStyles(src) {
  const stripped = stripDartComments(src);
  const parsed = {};
  for (const m of stripped.matchAll(
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
  return { parsed, candidates: tokenCandidates(stripped) };
}

/** Extract `token → number` pairs from a markdown table whose first column is
 *  a backticked token name and second column a `Nms`/`N` value. Scoped to the
 *  section between `heading` and the next `## `. */
export function parseMdTable(md, heading, tokenRe, candidateRe, allowRows = []) {
  const start = md.indexOf(heading);
  if (start === -1) throw new Error(`doc section not found: ${heading}`);
  const end = md.indexOf('\n## ', start + heading.length);
  const section = md.slice(start, end === -1 ? undefined : end);
  const out = {};
  for (const m of section.matchAll(tokenRe)) out[m[1]] = Number(m[2]);
  if (Object.keys(out).length === 0) {
    throw new Error(`no token rows matched under ${heading}`);
  }
  // The doc-table twin of the Dart candidate check (the review proved a
  // `600 ms` cell, a bolded value, or an unbackticked name silently vanished
  // from the mirror): every table row that MENTIONS a token of this family
  // must have parsed, or the row's format drifted from the regex.
  const candidates = [...section.matchAll(candidateRe)].filter(
    (m) => !allowRows.some((name) => m[0].includes(name)),
  );
  if (candidates.length !== Object.keys(out).length) {
    const parsedNames = new Set(Object.keys(out));
    const strays = candidates
      .map((m) => m[0].trim())
      .filter((row) => ![...parsedNames].some((n) => row.includes(n)));
    throw new Error(
      `${heading}: ${candidates.length} token rows in the table but only ` +
        `${Object.keys(out).length} parsed — a row's format drifted from the ` +
        `pin's regex. Suspect row(s): ${strays.join(' | ') || '(value-format deviation)'}`,
    );
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
  // A NEW file in the theme directory (a motion.dart when §9's Dart side
  // lands, a dark-mode palette…) is a token source this module doesn't read —
  // the gate forces the conscious decision instead of silently ignoring it.
  const themeDir = dirname(SOURCES.colors);
  const themeFiles = readdirSync(themeDir).sort();
  const KNOWN_THEME_FILES = [
    'app_theme.dart',
    'colors.dart',
    'motion.dart',
    'text_styles.dart',
  ];

  const colorsSrc = readFileSync(SOURCES.colors, 'utf8');
  const themeSrc = readFileSync(SOURCES.appTheme, 'utf8');
  const stylesSrc = readFileSync(SOURCES.textStyles, 'utf8');
  const motionSrc = readFileSync(SOURCES.motion, 'utf8');

  const colors = parseColors(colorsSrc);
  const doubles = parseDoubles(themeSrc);
  const styles = parseTextStyles(stylesSrc);
  const dartMotionParse = parseMotion(motionSrc);

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
    /^\|[^|\n]*motion\w+[^|\n]*\|.*$/gim,
  );
  const motion = {};
  for (const [name, ms] of Object.entries(motionDoc)) {
    motion[name[0].toLowerCase() + name.slice(1)] = `${ms}ms`;
  }

  const zIndexDoc = parseMdTable(
    readFileSync(SOURCES.webSystemDoc, 'utf8'),
    '### z-index',
    /\|\s*`z-(\w+)`\s*\|\s*(\d+)\s*\|/g,
    // Backtick OPTIONAL: an unbackticked `| z-tooltip | 60 |` row is exactly
    // the format drift the review landed past the first version.
    /^\|[^|\n]*\bz-\w+[^|\n]*\|.*$/gim,
    // `z-auto`'s value is the word `auto`, not a layer number — the declared
    // WEB_ONLY escape; its row is expected not to parse as a numeric pin.
    ['z-auto'],
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
    // The self-check inputs, surfaced for the gate's assertions: every
    // candidate declaration must be parsed by an idiom parser (there is no
    // legitimate non-token `static const|final … =` in these files today).
    parseChecks: [
      { file: 'colors.dart', candidates: colors.candidates, parsed: Object.keys(colors.parsed) },
      { file: 'app_theme.dart', candidates: doubles.candidates, parsed: Object.keys(doubles.parsed) },
      { file: 'text_styles.dart', candidates: styles.candidates, parsed: Object.keys(styles.parsed) },
      {
        file: 'motion.dart',
        candidates: dartMotionParse.candidates,
        parsed: [
          ...Object.keys(dartMotionParse.durations),
          ...Object.keys(dartMotionParse.curves),
        ],
      },
    ],
    // A8: the Dart side of §9 now exists, so the doc is no longer the ONLY
    // upstream — it is the shared one. The gate asserts doc === Dart === web,
    // which is what makes editing a number in any single place a red job.
    dartMotion: Object.fromEntries(
      Object.entries(dartMotionParse.durations).map(([k, ms]) => [k, `${ms}ms`]),
    ),
    dartMotionCurves: dartMotionParse.curves,
    themeFiles,
    knownThemeFiles: KNOWN_THEME_FILES,
    // Scalars the double-parse found that no family claims — the gate asserts
    // this is empty so a NEW AppTheme constant can't fall between families.
    unclaimedDoubles: Object.keys(doubles.parsed).filter(
      (k) => !(k in SPACING_KEYS) && !(k in RADIUS_KEYS) && !(k in ICON_KEYS),
    ),
  };
}

import { describe, expect, it } from 'vitest';
import {
  parseColors,
  parseDoubles,
  parseMdTable,
  parseTextStyles,
  stripDartComments,
} from '../scripts/dart-tokens.mjs';

/// B3 — the adversarial review's parser-evasion scenarios, pinned FOREVER.
///
/// The review defeated the first parser five distinct ways, every one proven
/// by live execution. Each scenario below is the review's own reproduction,
/// frozen as a fixture: if a refactor re-opens a hole, the exact attack that
/// found it goes red again.

describe('comments are not code (review findings #1/#2/#4)', () => {
  it('a commented-out declaration is DEAD — not parsed, not a candidate', () => {
    // The soft-delete: mobile removes starRating by commenting it while
    // deciding on a replacement. v1 kept it alive (regex matched inside the
    // comment) so the web mirror never heard about the removal.
    const src = `
  static const Color live = Color(0xFF111111);
  // static const Color starRating = Color(0xFFFFB800);
`;
    const { parsed, candidates } = parseColors(src);
    expect(parsed).toEqual({ live: '#111111' });
    expect(candidates).toEqual(['live']);
  });

  it('a stale field comment does not SHADOW the live field', () => {
    // v1 took the FIRST match in the TextStyle body — the comment's old value
    // won and a real mobile change shipped with the gate green.
    const src = `
  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 24 / 16,
    // letterSpacing: 0.15, — the old M3 value
    letterSpacing: 0.5,
  );
`;
    expect(parseTextStyles(src).parsed.titleMedium.letterSpacing).toBe(0.5);
  });

  it('a stale declaration comment AFTER the live line does not overwrite it', () => {
    // v1's last-match-wins made the web's CORRECT value look like drift.
    const src = `
  static const Color textDisabled = Color(0xFF9E9E9E);
  // was: static const Color textDisabled = Color(0xFFC0C0C0);
`;
    expect(parseColors(src).parsed.textDisabled).toBe('#9E9E9E');
  });

  it('a prose TODO mentioning the idiom is not a candidate (no permanent red)', () => {
    const src = `
  // TODO: add a static const Color infoDark when dark mode lands
  static const Color info = Color(0xFF1A1A2E);
`;
    const { parsed, candidates } = parseColors(src);
    expect(candidates).toEqual(['info']);
    expect(Object.keys(parsed)).toEqual(['info']);
  });

  it('the height division expression survives comment stripping', () => {
    expect(stripDartComments('height: 64 / 57,')).toBe('height: 64 / 57,');
  });
});

describe('non-idiom declarations are candidates that SCREAM (review finding #3)', () => {
  it('`static final Color` is a candidate the color parser does not claim', () => {
    // withValues() is not const-able, so `final` is genuinely forced — v1's
    // opener-count self-check never saw it and the token silently never
    // reached the web (the exact mechanism of drift #1, gold).
    const src = `
  static const Color primary = Color(0xFF000000);
  static final Color overlayScrim = Colors.black.withValues(alpha: 0.5);
`;
    const { parsed, candidates } = parseColors(src);
    expect(candidates).toEqual(['primary', 'overlayScrim']);
    expect(Object.keys(parsed)).toEqual(['primary']);
    // The gate's test asserts candidates ⊆ parsed — this is the red it sees:
    expect(candidates.filter((c) => !(c in parsed))).toEqual(['overlayScrim']);
  });

  it('a type-inferred `static const scrim = Color(…)` is a screaming candidate too', () => {
    const src = `static const scrim = Color(0xFF101010);`;
    const { parsed, candidates } = parseColors(src);
    expect(candidates).toEqual(['scrim']);
    expect(Object.keys(parsed)).toEqual([]);
  });

  it('getters and methods are not candidates (elevation1, textScaledBound)', () => {
    const src = `
  static const double spacingM = 16.0;
  static List<BoxShadow> get elevation1 => [BoxShadow()];
  static double textScaledBound(BuildContext c, {required double t}) => t;
`;
    expect(parseDoubles(src).candidates).toEqual(['spacingM']);
  });
});

describe('doc-table rows cannot vanish silently (review findings #5/#7/#12)', () => {
  const HEAD = '## 9. Motion';
  const MOTION_ROW = /\|\s*`motion(\w+)`\s*\|\s*(\d+)ms\s*\|/g;
  const MOTION_CANDIDATE = /^\|[^|\n]*motion\w+[^|\n]*\|.*$/gim;
  const table = (rows: string) => `${HEAD}\n\n| Token | Value |\n|---|---|\n${rows}\n`;

  it('a well-formed table parses', () => {
    expect(
      parseMdTable(
        table('| `motionFast` | 100ms |\n| `motionBase` | 200ms |'),
        HEAD,
        MOTION_ROW,
        MOTION_CANDIDATE,
      ),
    ).toEqual({ Fast: 100, Base: 200 });
  });

  it("a value-format drift (`600 ms` with a space) THROWS instead of vanishing", () => {
    expect(() =>
      parseMdTable(
        table('| `motionBase` | 200ms |\n| `motionXSlow` | 600 ms |'),
        HEAD,
        MOTION_ROW,
        MOTION_CANDIDATE,
      ),
    ).toThrow(/2 token rows.*only 1 parsed/s);
  });

  it('a bolded value cell THROWS instead of vanishing', () => {
    expect(() =>
      parseMdTable(
        table('| `motionBase` | **200ms** |'),
        HEAD,
        MOTION_ROW,
        MOTION_CANDIDATE,
      ),
    ).toThrow(/token rows/);
  });

  it('an unbackticked z-index row THROWS instead of vanishing', () => {
    const Z_ROW = /\|\s*`z-(\w+)`\s*\|\s*(\d+)\s*\|/g;
    const Z_CANDIDATE = /^\|[^|\n]*\bz-\w+[^|\n]*\|.*$/gim;
    expect(() =>
      parseMdTable(
        '### z-index\n\n| `z-base` | 0 |\n| z-tooltip | 60 |\n',
        '### z-index',
        Z_ROW,
        Z_CANDIDATE,
        ['z-auto'],
      ),
    ).toThrow(/token rows/);
  });
});

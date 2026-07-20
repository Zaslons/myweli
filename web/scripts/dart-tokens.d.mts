// Types for the plain-ESM parser (it stays .mjs so bare `node` can run
// gen-tokens.mjs without a TS toolchain; vitest + tsc consume it through this
// declaration).
export declare const SOURCES: Record<string, string>;
export declare const SPACING_KEYS: Record<string, string>;
export declare const RADIUS_KEYS: Record<string, string>;
export declare const ICON_KEYS: Record<string, string>;
export declare const WEB_ONLY: { spacing: string[]; motion: string[]; zIndex: string[] };

export declare function parseColors(src: string): {
  parsed: Record<string, string>;
  rawCount: number;
};
export declare function parseDoubles(src: string): {
  parsed: Record<string, number>;
  rawCount: number;
};
export declare function parseTextStyles(src: string): {
  parsed: Record<
    string,
    { fontSize: number; lineHeight: number; letterSpacing: number; fontWeight: string }
  >;
  rawCount: number;
};
export declare function parseMdTable(
  md: string,
  heading: string,
  tokenRe: RegExp,
): Record<string, number>;

export declare function expectedWebTokens(): {
  colors: Record<string, string>;
  spacing: Record<string, string>;
  radius: Record<string, string>;
  icon: Record<string, string>;
  type: Record<string, [string, { lineHeight: string; letterSpacing: string }]>;
  motion: Record<string, string>;
  zIndex: Record<string, string>;
  parseChecks: { file: string; raw: number; parsed: number }[];
  unclaimedDoubles: string[];
};

/// Types for the stub's time seam.
///
/// The seam itself is `.mjs` because `stub-api.mjs` is plain Node with no build
/// step — Playwright runs it directly, so it cannot import TypeScript. This
/// declaration is what lets `tests/stub-clock.test.ts` hold it to a contract
/// anyway.

export declare const TODAY: string;
export declare const TOMORROW: string;
export declare function stubDayKey(now?: Date, offsetDays?: number): string;
export declare function materialiseDates(serialised: string, now?: Date): string;

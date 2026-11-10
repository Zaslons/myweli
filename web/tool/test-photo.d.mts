/// Types for the salon page's test photo (`test-photo.mjs`, docs/design/web-swiss-salon.md
/// §1.1 item 9). The script is `.mjs` so it runs with plain Node and no build step; this
/// declaration lets `tests/test-photo.test.ts` hold it to a contract.

export declare const WIDTH: number;
export declare const HEIGHT: number;
export declare const QUALITY: number;
export declare const SEED: number;
export declare function drawTestPhoto(options?: {
  width?: number;
  height?: number;
  seed?: number;
}): { width: number; height: number; data: Buffer };
export declare function encodeTestPhoto(
  image: { width: number; height: number; data: Buffer },
  quality?: number,
): Buffer;

import { createHash } from 'node:crypto';
import jpeg from 'jpeg-js';
import { describe, expect, it } from 'vitest';

import {
  HEIGHT,
  WIDTH,
  drawTestPhoto,
  encodeTestPhoto,
} from '../tool/test-photo.mjs';

/// The salon page's test photo (docs/design/web-swiss-salon.md §1.1 item 9). It exists to
/// measure the cover's smaller request on a computer, which only shows with a source wider
/// than 828 px, and to be the one photo the PR may show. So it has to be what §1.9 says:
/// upright, at least 2048 px wide, at a real camera's weight, the same bytes every time.

const sha = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');

describe('the generated test photo', () => {
  it('is the same bytes every time, here and on any machine with this lockfile', () => {
    const once = encodeTestPhoto(drawTestPhoto({ width: 96, height: 128 }));
    const twice = encodeTestPhoto(drawTestPhoto({ width: 96, height: 128 }));
    expect(sha(twice)).toBe(sha(once));
    // Pinned: a clock, `Math.random` or an unlocked encoder would move it. A deliberate
    // change to the room moves it too, and the new hash is written here with it.
    expect(sha(once)).toBe('d622adb9d2e3ef46c4a430d2b28d08da5437cd9d0bc6d6baafb0aa9b1abf8a33');
  });

  it('is upright, at least 2048 px wide, and weighs what a camera’s photo does', () => {
    expect(WIDTH).toBeGreaterThanOrEqual(2048);
    expect(HEIGHT).toBeGreaterThan(WIDTH);
    const bytes = encodeTestPhoto(drawTestPhoto());
    // An 8-megapixel phone photo is about 2–3.5 MB. A flat drawing would weigh a tenth of
    // that and make the optimizer's work look cheaper than a salon's photo is.
    expect(bytes.length).toBeGreaterThan(1_500_000);
    expect(bytes.length).toBeLessThan(4_000_000);
    const decoded = jpeg.decode(bytes, { maxMemoryUsageInMB: 1024 });
    expect([decoded.width, decoded.height]).toEqual([WIDTH, HEIGHT]);
  }, 60_000);
});

import { describe, expect, it, vi } from 'vitest';

import {
  compressForUpload,
  type DecodedImage,
  type ImageHeader,
  megapixelBucket,
  NEED_MORE,
  orientationTransform,
  orientedSize,
  parseImageHeader,
  probeImageHeader,
  targetSize,
  UPLOAD_RULE,
} from '../lib/image/compress';

/// docs/design/web-pro-upload-resize.md §8.1 — the rule, the header reader and
/// the flow, behind the seams (jsdom has no canvas and no image decoder; the
/// browser work itself is exercised in real Chromium by
/// tests/e2e/pro-upload.spec.ts).

describe('the rule is the app’s (owner’s answer 1, 2026-11-09)', () => {
  it('pins the numbers: short ≤ 1600, long ≤ 2400, JPEG 0.80, 64 MP, 5 MiB', () => {
    // image_picker_sheet.dart: maxWidth/maxHeight 2400; api_image_upload_service.dart:
    // minWidth/minHeight 1600, quality 80; the server's claim-time cap 5 MiB.
    expect(UPLOAD_RULE).toEqual({
      longSide: 2400,
      shortSide: 1600,
      quality: 0.8,
      maxInputPixels: 64_000_000,
      maxBytes: 5_242_880,
    });
  });

  // §5.2's table (computed, and observed on the draft's fixtures), plus the
  // edges. `4800×3400` is the row where truncation and rounding part
  // (2258.8…), so it holds step 2's « floor ».
  const TABLE: [number, number, number, number][] = [
    [4032, 3024, 2133, 1600],
    [3024, 4032, 1600, 2133],
    [6048, 8064, 1600, 2133],
    [12000, 9000, 2133, 1600],
    [4000, 2250, 2400, 1350],
    [12000, 3000, 2400, 600],
    [6000, 4000, 2400, 1600],
    [3000, 3000, 1600, 1600],
    [2400, 1600, 2400, 1600],
    [1600, 2400, 1600, 2400],
    [600, 800, 600, 800],
    [8160, 6144, 2125, 1600],
    [4800, 3400, 2258, 1600],
    [2401, 100, 2400, 100],
    [1601, 1601, 1600, 1600],
    [1, 1, 1, 1],
    [20000, 1, 2400, 1],
  ];
  for (const [w, h, ew, eh] of TABLE) {
    it(`${w}×${h} → ${ew}×${eh}`, () => {
      expect(targetSize(w, h)).toEqual({ width: ew, height: eh });
    });
  }
});

/// The two plugin formulas, transcribed literally from the sources
/// `mobile/pubspec.lock` pins: image_picker_android 0.8.13+17
/// `ImageResizer.calculateTargetSize` (double, `Math.round`), then
/// flutter_image_compress_common 1.1.1 `BitmapCompressExt.calcScale` + `toInt()`
/// (Kotlin `Float` — hence `Math.fround`).
function pluginAndroid(w: number, h: number): [number, number] {
  const max = 2400;
  const aspectRatio = w / h;
  let width = Math.min(w, Math.round(max));
  let height = Math.min(h, Math.round(max));
  if (max < w || max < h) {
    const widthForMaxHeight = height * aspectRatio;
    const heightForMaxWidth = width / aspectRatio;
    if (heightForMaxWidth > height) width = Math.round(widthForMaxHeight);
    else height = Math.round(heightForMaxWidth);
  }
  const f = Math.fround;
  const fw = f(width);
  const fh = f(height);
  const scale = Math.max(1, Math.min(f(fw / f(1600)), f(fh / f(1600))));
  return [Math.trunc(f(fw / scale)), Math.trunc(f(fh / scale))];
}

function mulberry32(seed: number) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

describe('targetSize against the plugins, over thousands of sizes', () => {
  const rand = mulberry32(107);
  const sizes: [number, number][] = [];
  for (let k = 0; k < 6000; k++) {
    sizes.push([1 + Math.floor(rand() * 20000), 1 + Math.floor(rand() * 20000)]);
  }
  for (let s = 1590; s <= 2410; s++) sizes.push([s, 1600], [1600, s], [s, 2400], [2400, s]);

  it('never enlarges, keeps the caps and the orientation, and is maximal', () => {
    for (const [w, h] of sizes) {
      const t = targetSize(w, h);
      const long = Math.max(t.width, t.height);
      const short = Math.min(t.width, t.height);
      expect(t.width <= w && t.height <= h, `${w}×${h}`).toBe(true);
      expect(short <= 1600 && long <= 2400, `${w}×${h}`).toBe(true);
      expect(w >= h ? t.width >= t.height : t.width <= t.height, `${w}×${h}`).toBe(true);
      // Maximal: one cap is reached, or nothing had to shrink.
      const untouched = t.width === w && t.height === h;
      expect(short === 1600 || long === 2400 || untouched, `${w}×${h}`).toBe(true);
      // The proportions hold to within the two roundings: the side that was
      // derived is within 1 px (step 1's round) or 2 px (step 2's floor after
      // it) of the exact proportion — or the 1 px floor of an extreme panorama.
      const L = Math.max(w, h);
      const S = Math.min(w, h);
      const fits = Math.abs(short - (S * long) / L) <= 1 || Math.abs(long - (L * short) / S) <= 2;
      expect(fits || short === 1, `${w}×${h}`).toBe(true);
    }
  });

  it('matches the plugins to the pixel on camera sizes, and within 2 px anywhere', () => {
    let differ = 0;
    for (const [w, h] of sizes) {
      const [pw, ph] = pluginAndroid(w, h);
      if (ph === 0 || pw === 0) continue; // the app crashes there (a 0-px bitmap); the web keeps 1 px
      const t = targetSize(w, h);
      // 2 px: where step 1 lands on an exact half (12480×9529 → 1832.5), the
      // plugin's `w / h` ratio rounds it down, exact arithmetic up — and
      // step 2 carries that pixel onto the long side.
      expect(Math.abs(t.width - pw) <= 2 && Math.abs(t.height - ph) <= 2, `${w}×${h}`).toBe(true);
      if (t.width !== pw || t.height !== ph) differ += 1;
    }
    // The plugins' floating-point scale lands a pixel off on a minority of
    // random sizes (spec §5.2, « where the web knowingly differs »).
    expect(differ / sizes.length).toBeLessThan(0.1);
    for (const [w, h] of [
      [4032, 3024],
      [3024, 4032],
      [8000, 6000],
      [8160, 6144],
      [4080, 3072],
      [6048, 8064],
      [12000, 9000],
      [4000, 2250],
      [1920, 1080],
    ]) {
      const t = targetSize(w, h);
      expect([t.width, t.height], `${w}×${h}`).toEqual(pluginAndroid(w, h));
    }
  });
});

// ─── Header bytes, built by hand (no pixels needed) ──────────────────────────

const be16 = (n: number) => [(n >> 8) & 0xff, n & 0xff];
const le16 = (n: number) => [n & 0xff, (n >> 8) & 0xff];
const be32 = (n: number) => [(n >>> 24) & 0xff, (n >>> 16) & 0xff, (n >>> 8) & 0xff, n & 0xff];
const le32 = (n: number) => [n & 0xff, (n >>> 8) & 0xff, (n >>> 16) & 0xff, (n >>> 24) & 0xff];
const text = (s: string) => [...s].map((c) => c.charCodeAt(0));

function segment(marker: number, payload: number[]): number[] {
  return [0xff, marker, ...be16(payload.length + 2), ...payload];
}

/// APP1 Exif with one IFD0 entry: Orientation (0x0112, SHORT, 1).
function exifApp1(orientation: number, little: boolean): number[] {
  const w16 = little ? le16 : be16;
  const w32 = little ? le32 : be32;
  const tiff = [
    ...(little ? text('II') : text('MM')),
    ...w16(42),
    ...w32(8),
    ...w16(1),
    ...w16(0x0112),
    ...w16(3),
    ...w32(1),
    ...w16(orientation),
    0,
    0,
    ...w32(0),
  ];
  return segment(0xe1, [...text('Exif\0\0'), ...tiff]);
}

function jpeg(opts: {
  width: number;
  height: number;
  sof?: number;
  before?: number[][];
}): Uint8Array {
  const sof = segment(opts.sof ?? 0xc0, [8, ...be16(opts.height), ...be16(opts.width), 1, 1, 0x11, 0]);
  const parts = [[0xff, 0xd8], ...(opts.before ?? []), segment(0xdb, new Array(65).fill(1)), sof];
  parts.push(segment(0xda, [1, 1, 0, 0, 63, 0]), [0x00, 0xff, 0xd9]);
  return Uint8Array.from(parts.flat());
}

describe('parseImageHeader', () => {
  it('JPEG SOF0 with a little-endian Exif orientation 6: the STORED size + 6', () => {
    const b = jpeg({ width: 4032, height: 3024, before: [exifApp1(6, true)] });
    expect(parseImageHeader(b)).toEqual({ format: 'jpeg', width: 4032, height: 3024, orientation: 6 });
  });

  for (const o of [1, 3, 6, 8]) {
    it(`big-endian Exif, progressive SOF2: orientation ${o}`, () => {
      const b = jpeg({ width: 300, height: 200, sof: 0xc2, before: [exifApp1(o, false)] });
      expect(parseImageHeader(b)).toEqual({ format: 'jpeg', width: 300, height: 200, orientation: o });
    });
  }

  it('an APP1 that is XMP, not Exif, says nothing about orientation', () => {
    const xmp = segment(0xe1, text('http://ns.adobe.com/xap/1.0/\0<x:xmpmeta/>'));
    const b = jpeg({ width: 640, height: 480, before: [xmp] });
    expect(parseImageHeader(b)).toEqual({ format: 'jpeg', width: 640, height: 480, orientation: 1 });
  });

  it('an orientation out of 1–8 reads as 1', () => {
    const b = jpeg({ width: 10, height: 20, before: [exifApp1(9, true)] });
    expect(parseImageHeader(b)).toMatchObject({ orientation: 1 });
  });

  it('a JPEG cut before its frame header: « more » while reading, null when that was all', () => {
    const b = jpeg({ width: 10, height: 20, before: [exifApp1(6, true)] });
    const cut = b.slice(0, 30);
    expect(parseImageHeader(cut, false)).toBe(NEED_MORE);
    expect(parseImageHeader(cut, true)).toBeNull();
  });

  it('PNG IHDR', () => {
    const b = Uint8Array.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      ...be32(13), ...text('IHDR'), ...be32(1200), ...be32(900), 8, 6, 0, 0, 0,
    ]);
    expect(parseImageHeader(b)).toEqual({ format: 'png', width: 1200, height: 900, orientation: 1 });
  });

  const riff = (fourcc: string, body: number[]) =>
    Uint8Array.from([...text('RIFF'), ...le32(4 + 8 + body.length), ...text('WEBP'), ...text(fourcc), ...le32(body.length), ...body]);

  it('WebP VP8 (lossy)', () => {
    const b = riff('VP8 ', [0, 0, 0, 0x9d, 0x01, 0x2a, ...le16(4000), ...le16(2250), 0, 0]);
    expect(parseImageHeader(b)).toEqual({ format: 'webp', width: 4000, height: 2250, orientation: 1 });
  });

  it('WebP VP8L (lossless)', () => {
    const bits = (4000 - 1) | ((2250 - 1) << 14);
    const b = riff('VP8L', [0x2f, ...le32(bits >>> 0), 0, 0, 0, 0, 0]);
    expect(parseImageHeader(b)).toEqual({ format: 'webp', width: 4000, height: 2250, orientation: 1 });
  });

  it('WebP VP8X (extended)', () => {
    const b = riff('VP8X', [0, 0, 0, 0, ...le32(12000 - 1).slice(0, 3), ...le32(9000 - 1).slice(0, 3), 0, 0]);
    expect(parseImageHeader(b)).toEqual({ format: 'webp', width: 12000, height: 9000, orientation: 1 });
  });

  it('anything else is null: GIF, garbage, a renamed document, empty', () => {
    expect(parseImageHeader(Uint8Array.from(text('GIF89a\x01\x00\x01\x00')))).toBeNull();
    expect(parseImageHeader(Uint8Array.from(text('%PDF-1.7 hello')))).toBeNull();
    expect(parseImageHeader(Uint8Array.from([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))).toBeNull();
    expect(parseImageHeader(new Uint8Array(0))).toBeNull();
  });

  it('orientedSize turns 5–8 a quarter, not 1–4', () => {
    const h = (o: number): ImageHeader => ({ format: 'jpeg', width: 4032, height: 3024, orientation: o });
    for (const o of [1, 2, 3, 4]) expect(orientedSize(h(o))).toEqual({ width: 4032, height: 3024 });
    for (const o of [5, 6, 7, 8]) expect(orientedSize(h(o))).toEqual({ width: 3024, height: 4032 });
  });
});

describe('probeImageHeader reads only the start, and more when a JPEG needs it', () => {
  it('a frame header past 256 KiB of APP segments is still found', async () => {
    const pad = Array.from({ length: 5 }, () => segment(0xe2, new Array(65_000).fill(0x41)));
    const b = jpeg({ width: 8000, height: 9000, before: [exifApp1(6, true), ...pad] });
    expect(b.length).toBeGreaterThan(256 * 1024);
    const file = new File([b as BlobPart], 'x.jpg', { type: 'image/jpeg' });
    expect(await probeImageHeader(file)).toEqual({ format: 'jpeg', width: 8000, height: 9000, orientation: 6 });
  });
});

describe('orientationTransform — the last-resort rotation, EXIF’s eight cases', () => {
  // Where the STORED picture's first row / first column end up (EXIF 2.32,
  // tag 0x0112): o1 top/left · o2 top/right · o3 bottom/right · o4 bottom/left
  // · o5 left/top · o6 right/top · o7 right/bottom · o8 left/bottom.
  // So the stored top-left corner (0, 0) lands at:
  const W = 40;
  const H = 30; // the DISPLAYED size
  const TOP_LEFT_LANDS: Record<number, [number, number]> = {
    1: [0, 0],
    2: [W, 0],
    3: [W, H],
    4: [0, H],
    5: [0, 0],
    6: [W, 0],
    7: [W, H],
    8: [0, H],
  };
  // …and the stored top-right corner (drawWidth, 0):
  const TOP_RIGHT_LANDS: Record<number, [number, number]> = {
    1: [W, 0],
    2: [0, 0],
    3: [0, H],
    4: [W, H],
    5: [0, H],
    6: [W, H],
    7: [W, 0],
    8: [0, 0],
  };
  const apply = (t: ReturnType<typeof orientationTransform>, x: number, y: number) => [
    t.a * x + t.c * y + t.e,
    t.b * x + t.d * y + t.f,
  ];
  for (let o = 1; o <= 8; o++) {
    it(`orientation ${o}`, () => {
      const t = orientationTransform(o, W, H);
      const quarter = o >= 5;
      expect([t.drawWidth, t.drawHeight]).toEqual(quarter ? [H, W] : [W, H]);
      expect(apply(t, 0, 0).map((v) => v + 0)).toEqual(TOP_LEFT_LANDS[o]);
      expect(apply(t, t.drawWidth, 0).map((v) => v + 0)).toEqual(TOP_RIGHT_LANDS[o]);
      // The whole stored picture covers the canvas exactly.
      const far = apply(t, t.drawWidth, t.drawHeight).map((v) => v + 0);
      expect([far[0] === 0 || far[0] === W, far[1] === 0 || far[1] === H]).toEqual([true, true]);
    });
  }
});

describe('megapixelBucket — coarse bands only', () => {
  it.each([
    [null, 'unknown'],
    [0, 'unknown'],
    [11_999_999, '<12'],
    [12_000_000, '12-24'],
    [23_999_999, '12-24'],
    [24_000_000, '24-50'],
    [48_771_072, '24-50'],
    [50_135_040, '50-64'],
    [64_000_000, '50-64'],
    [64_000_001, '>64'],
    [108_000_000, '>64'],
  ] as const)('%s → %s', (pixels, bucket) => {
    expect(megapixelBucket(pixels)).toBe(bucket);
  });
});

// ─── The flow, with fake decode / encode ─────────────────────────────────────

function fakeImage(width: number, height: number) {
  const release = vi.fn();
  const image: DecodedImage = { source: {} as CanvasImageSource, width, height, orientation: 1, release };
  return { image, release };
}

const header = (width: number, height: number, orientation = 1): ImageHeader => ({
  format: 'jpeg',
  width,
  height,
  orientation,
});

const picked = new File(['x'], 'IMG_0001.jpg', { type: 'image/jpeg' });

describe('compressForUpload', () => {
  it('decodes AT the target size of the displayed picture, then encodes at that size', async () => {
    const { image, release } = fakeImage(1600, 2133);
    const decode = vi.fn(async () => image);
    const out = new Blob([new Uint8Array(1000)], { type: 'image/jpeg' });
    const encode = vi.fn(async () => out);
    const r = await compressForUpload(picked, { probe: async () => header(4032, 3024, 6), decode, encode });
    expect(decode).toHaveBeenCalledWith(picked, header(4032, 3024, 6), { width: 1600, height: 2133 });
    expect(encode).toHaveBeenCalledWith(image, { width: 1600, height: 2133 });
    expect(r).toEqual({ ok: true, blob: out, width: 1600, height: 2133, pixels: 4032 * 3024 });
    expect(release).toHaveBeenCalledTimes(1);
  });

  it('no header (GIF, BMP, AVIF…): decodes in full, then sizes from what was decoded', async () => {
    const { image } = fakeImage(4000, 2250);
    const decode = vi.fn(async () => image);
    const encode = vi.fn(async () => new Blob(['j']));
    const r = await compressForUpload(picked, { probe: async () => null, decode, encode });
    expect(decode).toHaveBeenCalledWith(picked, null, null);
    expect(encode).toHaveBeenCalledWith(image, { width: 2400, height: 1350 });
    expect(r).toMatchObject({ ok: true, width: 2400, height: 1350, pixels: 9_000_000 });
  });

  it('over 64 MP by its header: too_large, and NOTHING is decoded', async () => {
    const decode = vi.fn();
    const r = await compressForUpload(picked, { probe: async () => header(12000, 9000), decode, encode: vi.fn() });
    expect(r).toEqual({ ok: false, reason: 'too_large', pixels: 108_000_000 });
    expect(decode).not.toHaveBeenCalled();
  });

  it('exactly 64 MP is decoded (a 48 or 50 MP phone photo must pass)', async () => {
    const { image } = fakeImage(1600, 1600);
    const decode = vi.fn(async () => image);
    const r = await compressForUpload(picked, {
      probe: async () => header(8000, 8000),
      decode,
      encode: async () => new Blob(['j']),
    });
    expect(decode).toHaveBeenCalled();
    expect(r.ok).toBe(true);
  });

  it('the decoder refuses it: unreadable, and nothing is encoded', async () => {
    const encode = vi.fn();
    const r = await compressForUpload(picked, {
      probe: async () => null,
      decode: async () => {
        throw new DOMException('The source image could not be decoded.', 'InvalidStateError');
      },
      encode,
    });
    expect(r).toEqual({ ok: false, reason: 'unreadable', pixels: null });
    expect(encode).not.toHaveBeenCalled();
  });

  it('the encoder gives nothing, or throws: failed — and the bitmap is still released', async () => {
    for (const encode of [async () => null, async () => Promise.reject(new Error('oom'))]) {
      const { image, release } = fakeImage(100, 100);
      const r = await compressForUpload(picked, { probe: async () => header(100, 100), decode: async () => image, encode });
      expect(r).toEqual({ ok: false, reason: 'failed', pixels: 10_000 });
      expect(release).toHaveBeenCalledTimes(1);
    }
  });

  it('still over 5 MiB after preparing: too_large (never sent)', async () => {
    const { image } = fakeImage(2400, 1600);
    const big = new Blob([new Uint8Array(5 * 1024 * 1024 + 1)]);
    const r = await compressForUpload(picked, {
      probe: async () => header(2400, 1600),
      decode: async () => image,
      encode: async () => big,
    });
    expect(r).toEqual({ ok: false, reason: 'too_large', pixels: 2400 * 1600 });
    const exactly = new Blob([new Uint8Array(5 * 1024 * 1024)]);
    const ok = await compressForUpload(picked, {
      probe: async () => header(2400, 1600),
      decode: async () => fakeImage(2400, 1600).image,
      encode: async () => exactly,
    });
    expect(ok.ok).toBe(true);
  });

  it('a probe that throws is a picture with no known header, not a crash', async () => {
    const { image } = fakeImage(600, 800);
    const r = await compressForUpload(picked, {
      probe: async () => {
        throw new Error('read failed');
      },
      decode: async () => image,
      encode: async () => new Blob(['j']),
    });
    expect(r).toMatchObject({ ok: true, width: 600, height: 800 });
  });

  it('one at a time: a second picture waits for the first to finish', async () => {
    const order: string[] = [];
    let finishFirst: () => void = () => {};
    const firstDecoded = new Promise<void>((resolve) => {
      finishFirst = resolve;
    });
    const first = compressForUpload(picked, {
      probe: async () => {
        order.push('probe 1');
        return header(10, 10);
      },
      decode: async () => {
        await firstDecoded;
        order.push('decode 1');
        return fakeImage(10, 10).image;
      },
      encode: async () => new Blob(['1']),
    });
    const second = compressForUpload(picked, {
      probe: async () => {
        order.push('probe 2');
        return header(10, 10);
      },
      decode: async () => fakeImage(10, 10).image,
      encode: async () => new Blob(['2']),
    });
    await new Promise((r) => setTimeout(r, 20));
    expect(order).toEqual(['probe 1']);
    finishFirst();
    await Promise.all([first, second]);
    expect(order).toEqual(['probe 1', 'decode 1', 'probe 2']);
  });
});

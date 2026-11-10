// Design: docs/design/web-pro-upload-resize.md (decision 107)
import { colors } from '../../styles/tokens';

/// A photo picked on the website becomes the file the app would have uploaded.
///
/// The app never sends what was picked: `image_picker_sheet.dart` fits it in
/// 2400 × 2400 (`maxWidth`/`maxHeight`), then `api_image_upload_service.dart`
/// brings the short side down to 1600 (`flutter_image_compress`, `minWidth`/
/// `minHeight` 1600, `quality: 80`, JPEG), with the camera's orientation baked
/// into the pixels and no metadata written. The website used to PUT the `File`
/// itself: a 48 MP photo of 9 MB uploaded in full and was then refused at save
/// (the 5 MiB claim-time cap), and a camera JPEG kept its GPS position in a
/// public bucket. Owner's answer, 2026-11-09: « The app's exact rule ».
///
/// Runs in the browser, before anything is signed: read the header, refuse a
/// picture too big to decode safely, ask the browser how it shows the picture,
/// decode at the target size, draw on white, encode JPEG 0.80. One at a time,
/// on the main thread (no Worker: no long task was measured without one, §5.3
/// of the spec).
export const UPLOAD_RULE = {
  /// Step 1, the picker: the long side at most 2400, the short side rounded.
  longSide: 2400,
  /// Step 2, the compressor: the short side at most 1600, both sides truncated.
  shortSide: 1600,
  /// `quality: 80` in the app.
  quality: 0.8,
  /// The web's own ceiling, refused before decoding (64 MP, decimal): a
  /// browser cannot subsample on decode as the app does, and a phone's tab
  /// killed for memory loses the Profil form's unsaved edits.
  maxInputPixels: 64_000_000,
  /// The server's claim-time cap (`UploadVerificationService`), 5 MiB.
  maxBytes: 5 * 1024 * 1024,
} as const;

export type Size = { width: number; height: number };

/// The app's arithmetic on the displayed (orientation-corrected) size:
/// the short side at most 1600 and the long side at most 2400, never enlarged.
///
///     if long  > 2400: short = round(short × 2400 / long); long = 2400
///     if short > 1600: long = floor(long × 1600 / short);  short = 1600
///
/// Exact integer arithmetic: the plugins divide by a floating-point scale and
/// land one pixel short on some sizes (1599 instead of 1600); none of the
/// usual camera sizes is among them (spec §5.2).
export function targetSize(width: number, height: number): Size {
  const landscape = width >= height;
  let long = Math.max(width, height);
  let short = Math.min(width, height);
  if (long > UPLOAD_RULE.longSide) {
    short = Math.max(1, Math.round((short * UPLOAD_RULE.longSide) / long));
    long = UPLOAD_RULE.longSide;
  }
  if (short > UPLOAD_RULE.shortSide) {
    long = Math.max(1, Math.floor((long * UPLOAD_RULE.shortSide) / short));
    short = UPLOAD_RULE.shortSide;
  }
  return landscape ? { width: long, height: short } : { width: short, height: long };
}

/// What the header says, before any pixel is decoded: the STORED size and
/// the EXIF orientation as this module reads it (1–8; 1 when absent or
/// unreadable). The orientation is only used when the browser applies none
/// itself (the last-resort path): otherwise the browser's own reading wins
/// (`measure`, review F1 of 2026-11-09).
export type ImageHeader = {
  format: 'jpeg' | 'png' | 'webp' | 'gif' | 'bmp' | 'avif' | 'heic';
  width: number;
  height: number;
  orientation: number;
};

/// The size the picture is displayed at: orientations 5–8 turn it a quarter.
export function orientedSize(header: ImageHeader): Size {
  const quarter = header.orientation >= 5 && header.orientation <= 8;
  return quarter
    ? { width: header.height, height: header.width }
    : { width: header.width, height: header.height };
}

/// The walk ran out of bytes before the size: read more.
export const NEED_MORE = 'more' as const;

const u16be = (b: Uint8Array, i: number) => (b[i] << 8) | b[i + 1];
const u16le = (b: Uint8Array, i: number) => b[i] | (b[i + 1] << 8);
const u32be = (b: Uint8Array, i: number) =>
  ((b[i] << 24) >>> 0) + ((b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]);
const u32le = (b: Uint8Array, i: number) =>
  (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)) >>> 0;
const i32le = (b: Uint8Array, i: number) => b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);
const ascii = (b: Uint8Array, i: number, s: string) =>
  i + s.length <= b.length && [...s].every((c, k) => b[i + k] === c.charCodeAt(0));
const fourcc = (b: Uint8Array, i: number) => String.fromCharCode(b[i], b[i + 1], b[i + 2], b[i + 3]);

/// The brands of an ISO-BMFF file that are a still picture this module sizes.
const HEIF_BRANDS = ['avif', 'avis', 'heic', 'heix', 'heim', 'heis', 'hevc', 'hevx', 'mif1', 'msf1'];

/// Reads the size of a JPEG (SOFn, and the first APP1 Exif's orientation), a
/// PNG (IHDR, and an `eXIf` before the image data), a WebP (VP8, VP8L, VP8X),
/// a GIF, a BMP and an AVIF/HEIC (the largest `ispe`) from the first bytes of
/// a file. Anything else is `null` — and is never decoded (review F2/F6: the
/// 64 MP ceiling must hold for every picture that reaches the decoder).
/// `complete` says the bytes are the whole file; when they are not and the
/// size lies further on, the answer is `NEED_MORE`.
export function parseImageHeader(
  b: Uint8Array,
  complete = true,
): ImageHeader | null | typeof NEED_MORE {
  if (b.length >= 24 && u32be(b, 0) === 0x89504e47 && u32be(b, 4) === 0x0d0a1a0a) {
    if (!ascii(b, 12, 'IHDR')) return null;
    return sized('png', u32be(b, 16), u32be(b, 20), pngOrientation(b));
  }
  if (b.length >= 30 && ascii(b, 0, 'RIFF') && ascii(b, 8, 'WEBP')) {
    if (ascii(b, 12, 'VP8X')) {
      const w = 1 + (b[24] | (b[25] << 8) | (b[26] << 16));
      const h = 1 + (b[27] | (b[28] << 8) | (b[29] << 16));
      return sized('webp', w, h, 1);
    }
    if (ascii(b, 12, 'VP8 ')) {
      if (b[23] !== 0x9d || b[24] !== 0x01 || b[25] !== 0x2a) return null;
      return sized('webp', u16le(b, 26) & 0x3fff, u16le(b, 28) & 0x3fff, 1);
    }
    if (ascii(b, 12, 'VP8L')) {
      if (b[20] !== 0x2f) return null;
      const bits = (b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24)) >>> 0;
      return sized('webp', 1 + (bits & 0x3fff), 1 + ((bits >>> 14) & 0x3fff), 1);
    }
    return null;
  }
  if (b.length >= 10 && (ascii(b, 0, 'GIF87a') || ascii(b, 0, 'GIF89a'))) {
    // The logical screen; a frame drawn larger is caught by `measure`.
    return sized('gif', u16le(b, 6), u16le(b, 8), 1);
  }
  if (b.length >= 26 && b[0] === 0x42 && b[1] === 0x4d) {
    const dib = u32le(b, 14);
    if (dib === 12) return sized('bmp', u16le(b, 18), u16le(b, 20), 1);
    // A negative height is a top-down BMP: the size drops the sign.
    if (dib >= 40) return sized('bmp', Math.abs(i32le(b, 18)), Math.abs(i32le(b, 22)), 1);
    return null;
  }
  if (b.length >= 12 && ascii(b, 4, 'ftyp')) return heifHeader(b, complete);
  if (b.length < 2 || b[0] !== 0xff || b[1] !== 0xd8) return null;
  let i = 2;
  let orientation = 1;
  let exifSeen = false;
  for (;;) {
    if (i + 4 > b.length) return complete ? null : NEED_MORE;
    if (b[i] !== 0xff) return null;
    const marker = b[i + 1];
    if (marker === 0xff) {
      i += 1; // fill byte
      continue;
    }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8)) {
      i += 2; // standalone marker, no length
      continue;
    }
    if (marker === 0xd9 || marker === 0xda) return null; // EOI / SOS before any frame
    const length = u16be(b, i + 2);
    if (length < 2) return null;
    const end = i + 2 + length;
    // The FIRST Exif segment is the one browsers read (Chromium, measured by
    // the review: « 6 then 1 » shows portrait, « 1 then 6 » landscape).
    if (marker === 0xe1 && !exifSeen && ascii(b, i + 4, 'Exif\0\0')) {
      if (end > b.length) return complete ? null : NEED_MORE;
      orientation = tiffOrientation(b, i + 10, end);
      exifSeen = true;
    }
    const isFrame = marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
    if (isFrame) {
      if (i + 9 > b.length) return complete ? null : NEED_MORE;
      return sized('jpeg', u16be(b, i + 7), u16be(b, i + 5), orientation);
    }
    i = end;
  }
}

function sized(format: ImageHeader['format'], width: number, height: number, orientation: number) {
  return width > 0 && height > 0 ? { format, width, height, orientation } : null;
}

/// The Orientation tag (0x0112) of IFD0, from the TIFF header at `t`: a SHORT
/// with one value, as the browsers require (a LONG is ignored — measured).
function tiffOrientation(b: Uint8Array, t: number, end: number): number {
  if (t + 8 > end) return 1;
  const little = b[t] === 0x49 && b[t + 1] === 0x49;
  if (!little && !(b[t] === 0x4d && b[t + 1] === 0x4d)) return 1;
  const r16 = (i: number) => (little ? u16le(b, i) : u16be(b, i));
  const r32 = (i: number) => (little ? u32le(b, i) : u32be(b, i));
  if (r16(t + 2) !== 42) return 1;
  const ifd = t + r32(t + 4);
  if (ifd + 2 > end) return 1;
  const count = r16(ifd);
  for (let k = 0; k < count; k++) {
    const e = ifd + 2 + k * 12;
    if (e + 12 > end) return 1;
    if (r16(e) === 0x0112) {
      if (r16(e + 2) !== 3 || r32(e + 4) !== 1) return 1;
      const value = r16(e + 8);
      return value >= 1 && value <= 8 ? value : 1;
    }
  }
  return 1;
}

/// A PNG's `eXIf` orientation, when the chunk comes before the image data
/// (after it, browsers ignore it — measured by the review in Chromium).
function pngOrientation(b: Uint8Array): number {
  for (let i = 8; i + 8 <= b.length; ) {
    const length = u32be(b, i);
    const type = fourcc(b, i + 4);
    if (type === 'IDAT' || type === 'IEND') return 1;
    if (type === 'eXIf') {
      const end = i + 8 + length;
      return end <= b.length ? tiffOrientation(b, i + 8, end) : 1;
    }
    i += 12 + length;
  }
  return 1;
}

type Box = { type: string; start: number; end: number };

/// The child boxes of an ISO-BMFF range. `cut` says a box ran past the bytes.
function childBoxes(b: Uint8Array, from: number, to: number): { boxes: Box[]; cut: boolean } {
  const boxes: Box[] = [];
  let i = from;
  while (i + 8 <= to) {
    let size = u32be(b, i);
    let head = 8;
    if (size === 1) {
      if (i + 16 > to) return { boxes, cut: true };
      size = u32be(b, i + 8) * 2 ** 32 + u32be(b, i + 12);
      head = 16;
    } else if (size === 0) {
      size = to - i;
    }
    if (size < head) return { boxes, cut: false };
    boxes.push({ type: fourcc(b, i + 4), start: i + head, end: i + size });
    i += size;
  }
  return { boxes, cut: i < to || i > b.length };
}

/// AVIF / HEIC: the brand, then the largest `ispe` (image spatial extent) in
/// `meta` → `iprp` → `ipco` — for a tiled picture that is the whole canvas,
/// never a tile, so the ceiling sees the real size. The rotation (`irot`) is
/// not read: the browser's own reading of the displayed size wins (`measure`).
function heifHeader(b: Uint8Array, complete: boolean): ImageHeader | null | typeof NEED_MORE {
  const ftyp = u32be(b, 0);
  if (ftyp < 16 || ftyp > b.length) return complete ? null : NEED_MORE;
  const brands = [fourcc(b, 8)];
  for (let i = 16; i + 4 <= ftyp; i += 4) brands.push(fourcc(b, i));
  if (!brands.some((x) => HEIF_BRANDS.includes(x))) return null;
  const format = brands.some((x) => x === 'avif' || x === 'avis') ? 'avif' : 'heic';
  const top = childBoxes(b, 0, b.length);
  const meta = top.boxes.find((x) => x.type === 'meta');
  if (!meta || meta.end > b.length) return complete ? null : NEED_MORE;
  const iprp = childBoxes(b, meta.start + 4, meta.end).boxes.find((x) => x.type === 'iprp');
  const ipco = iprp && childBoxes(b, iprp.start, iprp.end).boxes.find((x) => x.type === 'ipco');
  if (!ipco) return null;
  let best: Size | null = null;
  for (const box of childBoxes(b, ipco.start, ipco.end).boxes) {
    if (box.type !== 'ispe' || box.start + 12 > box.end) continue;
    const width = u32be(b, box.start + 4);
    const height = u32be(b, box.start + 8);
    if (!best || width * height > best.width * best.height) best = { width, height };
  }
  return best ? sized(format, best.width, best.height, 1) : null;
}

/// `Blob.arrayBuffer` where it exists; `FileReader` otherwise (older Safari).
function readBytes(blob: Blob): Promise<ArrayBuffer> {
  if (typeof blob.arrayBuffer === 'function') return blob.arrayBuffer();
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as ArrayBuffer);
    reader.onerror = () => reject(reader.error);
    reader.readAsArrayBuffer(blob);
  });
}

const PROBE_FIRST = 256 * 1024;
const PROBE_LAST = 4 * 1024 * 1024;

/// The header of a picked file, reading only its first bytes (256 KiB, then up
/// to 4 MiB when the size lies further on). `null` when unknown.
export async function probeImageHeader(file: Blob): Promise<ImageHeader | null> {
  for (let n = PROBE_FIRST; ; n *= 4) {
    const complete = n >= file.size;
    const bytes = new Uint8Array(await readBytes(file.slice(0, n)));
    const header = parseImageHeader(bytes, complete);
    if (header !== NEED_MORE) return header;
    if (complete || n >= PROBE_LAST) return null;
  }
}

/// A picture's size in coarse bands, for telemetry only — never to the pixel.
export type MegapixelBucket = '<12' | '12-24' | '24-50' | '50-64' | '>64' | 'unknown';

export function megapixelBucket(pixels: number | null): MegapixelBucket {
  if (pixels === null || !Number.isFinite(pixels) || pixels <= 0) return 'unknown';
  const mp = pixels / 1_000_000;
  if (mp < 12) return '<12';
  if (mp < 24) return '12-24';
  if (mp < 50) return '24-50';
  if (mp <= 64) return '50-64';
  return '>64';
}

/// The canvas matrix that shows a STORED picture as its EXIF orientation
/// says, on a canvas of the displayed size `width` × `height`; the picture is
/// drawn at `drawWidth` × `drawHeight` (its stored axes). Only the last-resort
/// path uses it: an engine whose decoders ignore EXIF orientation.
export function orientationTransform(orientation: number, width: number, height: number) {
  const quarter = orientation >= 5 && orientation <= 8;
  const draw = quarter
    ? { drawWidth: height, drawHeight: width }
    : { drawWidth: width, drawHeight: height };
  const m: Record<number, [number, number, number, number, number, number]> = {
    2: [-1, 0, 0, 1, width, 0],
    3: [-1, 0, 0, -1, width, height],
    4: [1, 0, 0, -1, 0, height],
    5: [0, 1, 1, 0, 0, 0],
    6: [0, 1, -1, 0, width, 0],
    7: [0, -1, -1, 0, width, height],
    8: [0, -1, 1, 0, 0, height],
  };
  const [a, b, c, d, e, f] = m[orientation] ?? [1, 0, 0, 1, 0, 0];
  return { a, b, c, d, e, f, ...draw };
}

/// Whether read-back pixels still show the expected colours, each channel
/// within `tolerance`: a JPEG round trip and the small per-pixel noise some
/// browsers add against fingerprinting pass; a blank or random read-back does
/// not. `pixels` is RGBA; `expected` lists [index of the pixel, [r, g, b]].
export function pixelsMatch(
  pixels: ArrayLike<number>,
  expected: [number, [number, number, number]][],
  tolerance = 48,
): boolean {
  return expected.every(([at, rgb]) =>
    rgb.every((v, k) => Math.abs(pixels[at * 4 + k] - v) <= tolerance),
  );
}

/// A decoded picture, ready to draw. `width` × `height` is the size it draws
/// at with no matrix; `orientation` is what is still to apply (1 = none).
export type DecodedImage = {
  source: CanvasImageSource;
  width: number;
  height: number;
  orientation: number;
  release: () => void;
};

/// `blocked`: the browser alters what a canvas gives back (anti-fingerprinting
/// in Firefox, Tor, Brave's strict mode), so the prepared file would be blank
/// or noise — refused rather than sent (review F4).
export type PrepareFailure = 'unreadable' | 'too_large' | 'blocked' | 'failed';

export type PrepareResult =
  | { ok: true; blob: Blob; width: number; height: number; pixels: number | null }
  | { ok: false; reason: PrepareFailure; pixels: number | null };

/// The seams — the app's `ImageCompressor` idea: the flow is unit-testable
/// without a canvas (jsdom has none); the defaults are the browser's.
export type CompressDeps = {
  probe?: (file: Blob) => Promise<ImageHeader | null>;
  /// The size the BROWSER shows the picture at (its own orientation reading).
  measure?: (file: Blob, header: ImageHeader) => Promise<Size>;
  /// Whether a canvas gives back what was drawn on it.
  canvasWorks?: () => Promise<boolean>;
  decode?: (file: Blob, header: ImageHeader, target: Size) => Promise<DecodedImage>;
  encode?: (image: DecodedImage, target: Size) => Promise<Blob | null>;
  maxBytes?: number;
};

async function prepare(file: Blob, deps: Required<CompressDeps>): Promise<PrepareResult> {
  let header: ImageHeader | null = null;
  try {
    header = await deps.probe(file);
  } catch {
    header = null;
  }
  // Only a picture whose size is known is decoded: the ceiling below must
  // hold for everything that reaches the decoder (review F2), and a renamed
  // document of any size is never handed to it (F6).
  if (!header) return { ok: false, reason: 'unreadable', pixels: null };
  let pixels = header.width * header.height;
  if (pixels > UPLOAD_RULE.maxInputPixels) return { ok: false, reason: 'too_large', pixels };

  // The browser's reading, not ours: two Exif segments, a LONG-typed tag, a
  // PNG `eXIf`, an AVIF `irot` — wherever the two could differ, the picture
  // would be squeezed into the other orientation's frame (review F1).
  let shown: Size;
  try {
    shown = await deps.measure(file, header);
  } catch {
    return { ok: false, reason: 'unreadable', pixels };
  }
  pixels = Math.max(pixels, shown.width * shown.height);
  if (pixels > UPLOAD_RULE.maxInputPixels) return { ok: false, reason: 'too_large', pixels };
  if (!(await deps.canvasWorks().catch(() => false))) return { ok: false, reason: 'blocked', pixels };
  const target = targetSize(shown.width, shown.height);

  let image: DecodedImage;
  try {
    image = await deps.decode(file, header, target);
  } catch {
    return { ok: false, reason: 'unreadable', pixels };
  }
  let blob: Blob | null = null;
  try {
    blob = await deps.encode(image, target);
  } catch {
    blob = null;
  } finally {
    image.release();
  }
  // An engine that cannot write JPEG falls back to PNG (the canvas rule):
  // those bytes must never go out signed as `image/jpeg` (review F8).
  if (!blob || blob.type !== 'image/jpeg') return { ok: false, reason: 'failed', pixels };
  if (blob.size > deps.maxBytes) return { ok: false, reason: 'too_large', pixels };
  return { ok: true, blob, width: target.width, height: target.height, pixels };
}

let queue: Promise<void> = Promise.resolve();

/// Prepares one picked picture for upload. **One at a time**: « Avant » and
/// « Après » picked back to back would otherwise decode together and double
/// the memory peak on a phone. Never throws.
export function compressForUpload(file: Blob, deps: CompressDeps = {}): Promise<PrepareResult> {
  const all: Required<CompressDeps> = {
    probe: deps.probe ?? probeImageHeader,
    measure: deps.measure ?? measureInBrowser,
    canvasWorks: deps.canvasWorks ?? canvasWorksInBrowser,
    decode: deps.decode ?? decodeInBrowser,
    encode: deps.encode ?? encodeOnWhite,
    maxBytes: deps.maxBytes ?? UPLOAD_RULE.maxBytes,
  };
  const run = queue.then(() =>
    prepare(file, all).catch((): PrepareResult => ({ ok: false, reason: 'failed', pixels: null })),
  );
  // The queue keeps the order, not the last result (its file is the caller's).
  queue = run.then(() => undefined);
  return run;
}

// ─── The browser implementation ─────────────────────────────────────────────

/// 16 × 8 JPEG tagged EXIF orientation 6 (198 bytes), its left half black and
/// its right half white: an engine that applies EXIF orientation shows it
/// 8 × 16, black above white.
const ORIENTED_PROBE =
  '/9j/4AAQSkZJRgABAQAAAQABAAD/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAYAAAAAAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/wAALCAAIABABAREA/8QAFQABAQAAAAAAAAAAAAAAAAAACQr/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAA/ACqVUP/Z';

type Engine = { decoder: 'bitmap' | 'img' | 'manual'; imgOrients: boolean };
let engine: Promise<Engine> | null = null;

type AnyCanvas = OffscreenCanvas | HTMLCanvasElement;
type Any2d = CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D;

function makeCanvas(width: number, height: number): AnyCanvas {
  if (typeof OffscreenCanvas === 'function') return new OffscreenCanvas(width, height);
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  return canvas;
}

/// Gives the canvas memory back now rather than at the next collection.
function dropCanvas(canvas: AnyCanvas): void {
  canvas.width = 0;
  canvas.height = 0;
}

/// The RGBA pixels of `source` drawn at `width` × `height`, or null.
function readBack(source: CanvasImageSource, width: number, height: number): Uint8ClampedArray | null {
  const canvas = makeCanvas(width, height);
  try {
    const ctx = canvas.getContext('2d', { willReadFrequently: true }) as Any2d | null;
    if (!ctx) return null;
    ctx.drawImage(source, 0, 0, width, height);
    return ctx.getImageData(0, 0, width, height).data;
  } finally {
    dropCanvas(canvas);
  }
}

/// Which decoder applies EXIF orientation, checked once. `createImageBitmap`
/// is used only if it orients the probe WHEN ASKED FOR A SIZE — the way it is
/// called — both in its shape and in its pixels (black above white: an engine
/// that dropped the orientation while scaling would give the right shape with
/// the picture sideways). Else `<img>` (CSS `image-orientation: from-image`),
/// else rotate on the canvas ourselves. `imgOrients` says whether `<img>`'s
/// own size can be trusted as the displayed size.
function detectEngine(): Promise<Engine> {
  engine ??= (async (): Promise<Engine> => {
    const bytes = Uint8Array.from(atob(ORIENTED_PROBE), (c) => c.charCodeAt(0));
    const probe = new Blob([bytes], { type: 'image/jpeg' });
    let imgOrients = false;
    try {
      const size = await naturalSize(probe);
      imgOrients = size.width === 8 && size.height === 16;
    } catch {
      // no <img> either: the last resort below
    }
    if (typeof createImageBitmap === 'function') {
      try {
        const bitmap = await createImageBitmap(probe, {
          imageOrientation: 'from-image',
          resizeWidth: 4,
          resizeHeight: 8,
          resizeQuality: 'high',
        });
        try {
          const px = bitmap.width === 4 && bitmap.height === 8 ? readBack(bitmap, 4, 8) : null;
          const black: [number, number, number] = [0, 0, 0];
          const white: [number, number, number] = [255, 255, 255];
          // Rows 1 and 6, both edges: black above, white below.
          const upright =
            !!px && pixelsMatch(px, [[4, black], [7, black], [24, white], [27, white]], 64);
          if (upright) return { decoder: 'bitmap', imgOrients };
        } finally {
          bitmap.close();
        }
      } catch {
        // fall through to <img>
      }
    }
    return { decoder: imgOrients ? 'img' : 'manual', imgOrients };
  })();
  return engine;
}

/// The size `<img>` gives a file once loaded — the displayed size where it
/// orients — read on `load`, which needs the header only (`decode()` is never
/// called here: no full decode).
function naturalSize(file: Blob): Promise<Size> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const el = new Image();
    const finish = () => {
      el.onload = null;
      el.onerror = null;
      el.removeAttribute('src');
      URL.revokeObjectURL(url);
    };
    el.onload = () => {
      const size = { width: el.naturalWidth, height: el.naturalHeight };
      finish();
      if (size.width > 0 && size.height > 0) resolve(size);
      else reject(new Error('no size'));
    };
    el.onerror = () => {
      finish();
      reject(new Error('not an image'));
    };
    el.src = url;
  });
}

/// The displayed size, as the browser will decode it: `<img>`'s own size where
/// `<img>` orients, else the header turned by our own reading (the last-resort
/// path rotates with that same reading, so the two agree by construction).
async function measureInBrowser(file: Blob, header: ImageHeader): Promise<Size> {
  const { imgOrients } = await detectEngine();
  return imgOrients ? naturalSize(file) : orientedSize(header);
}

/// The swatches of the canvas check: four colours of the palette, none white,
/// so neither a blank read-back nor random noise matches all four.
const SWATCHES = [colors.primary, colors.errorLight, colors.warningLight, colors.infoLight];

const rgbOf = (hex: string): [number, number, number] => [
  parseInt(hex.slice(1, 3), 16),
  parseInt(hex.slice(3, 5), 16),
  parseInt(hex.slice(5, 7), 16),
];

let canvasChecked: Promise<boolean> | null = null;

/// Whether this browser's canvas gives back what was drawn on it: four 16 px
/// squares go through the real path (canvas → JPEG → decode → read back) and
/// must come back within tolerance. A pass is kept for the session; a refusal
/// is checked again next time (a permission prompt may have been answered).
function canvasWorksInBrowser(): Promise<boolean> {
  canvasChecked ??= (async () => {
    const canvas = makeCanvas(32, 32);
    let jpeg: Blob | null = null;
    try {
      const ctx = canvas.getContext('2d') as Any2d | null;
      if (!ctx) return false;
      SWATCHES.forEach((hex, k) => {
        ctx.fillStyle = hex;
        ctx.fillRect((k % 2) * 16, Math.floor(k / 2) * 16, 16, 16);
      });
      jpeg = await toJpeg(canvas, 0.9);
    } finally {
      dropCanvas(canvas);
    }
    if (!jpeg || jpeg.type !== 'image/jpeg') return false;
    const image = await decodePlain(jpeg);
    try {
      const px = readBack(image.source, 32, 32);
      // The centre of each square: (8, 8), (24, 8), (8, 24), (24, 24).
      const centres = [8 * 32 + 8, 8 * 32 + 24, 24 * 32 + 8, 24 * 32 + 24];
      return !!px && pixelsMatch(px, SWATCHES.map((hex, k) => [centres[k], rgbOf(hex)]));
    } finally {
      image.release();
    }
  })().catch(() => false);
  const check = canvasChecked;
  void check.then((ok) => {
    if (!ok && canvasChecked === check) canvasChecked = null;
  });
  return check;
}

/// A small picture decoded as is (no orientation involved).
async function decodePlain(file: Blob): Promise<DecodedImage> {
  if (typeof createImageBitmap === 'function') return fromBitmap(await createImageBitmap(file));
  const img = await loadImage(file);
  return { source: img.el, width: img.el.naturalWidth, height: img.el.naturalHeight, orientation: 1, release: img.release };
}

async function loadImage(file: Blob): Promise<{ el: HTMLImageElement; release: () => void }> {
  const url = URL.createObjectURL(file);
  const el = new Image();
  el.decoding = 'async';
  el.src = url;
  const release = () => {
    el.removeAttribute('src');
    URL.revokeObjectURL(url);
  };
  try {
    await el.decode();
  } catch (error) {
    release();
    throw error;
  }
  return { el, release };
}

function fromBitmap(bitmap: ImageBitmap): DecodedImage {
  return {
    source: bitmap,
    width: bitmap.width,
    height: bitmap.height,
    orientation: 1,
    release: () => bitmap.close(),
  };
}

/// Decodes AT THE TARGET SIZE — about half the memory peak of a full-size
/// decode (measured, spec §5.3) — and never allocates a canvas at the source
/// size.
async function decodeInBrowser(file: Blob, header: ImageHeader, target: Size): Promise<DecodedImage> {
  const { decoder } = await detectEngine();
  if (decoder === 'bitmap') {
    try {
      return fromBitmap(
        await createImageBitmap(file, {
          imageOrientation: 'from-image',
          resizeWidth: target.width,
          resizeHeight: target.height,
          resizeQuality: 'high',
        }),
      );
    } catch {
      // An engine that refuses `resizeWidth`/`resizeHeight`: decode at full size.
    }
    return fromBitmap(await createImageBitmap(file, { imageOrientation: 'from-image' }));
  }
  const img = await loadImage(file);
  const orientation = decoder === 'manual' ? header.orientation : 1;
  const quarter = orientation >= 5 && orientation <= 8;
  const { naturalWidth: w, naturalHeight: h } = img.el;
  return {
    source: img.el,
    width: quarter ? h : w,
    height: quarter ? w : h,
    orientation,
    release: img.release,
  };
}

function toJpeg(canvas: AnyCanvas, quality: number): Promise<Blob | null> {
  if ('convertToBlob' in canvas) return canvas.convertToBlob({ type: 'image/jpeg', quality });
  return new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality));
}

/// Draws on white — a transparent pixel would otherwise become BLACK in a
/// JPEG (measured) — then encodes JPEG at the app's quality. A canvas encode
/// writes no EXIF: the metadata (GPS included) goes by construction. The
/// picture is drawn at the target size whatever size it was decoded at.
async function encodeOnWhite(image: DecodedImage, target: Size): Promise<Blob | null> {
  const { width, height } = target;
  const canvas = makeCanvas(width, height);
  try {
    const ctx = canvas.getContext('2d') as Any2d | null;
    if (!ctx) return null;
    ctx.fillStyle = colors.secondary;
    ctx.fillRect(0, 0, width, height);
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    const t = orientationTransform(image.orientation, width, height);
    ctx.setTransform(t.a, t.b, t.c, t.d, t.e, t.f);
    ctx.drawImage(image.source, 0, 0, t.drawWidth, t.drawHeight);
    return await toJpeg(canvas, UPLOAD_RULE.quality);
  } finally {
    dropCanvas(canvas);
  }
}

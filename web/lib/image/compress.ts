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
/// picture too big to decode safely, decode at the target size, draw on white,
/// encode JPEG 0.80. One at a time, on the main thread (no Worker: no long task
/// was measured without one, §5.3 of the spec).
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

/// What the header says, before any pixel is decoded: the STORED size and,
/// for a JPEG, the EXIF orientation (1–8; 1 when absent or unreadable).
export type ImageHeader = {
  format: 'jpeg' | 'png' | 'webp';
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

/// The JPEG walk ran out of bytes before the frame header: read more.
export const NEED_MORE = 'more' as const;

const u16be = (b: Uint8Array, i: number) => (b[i] << 8) | b[i + 1];
const u16le = (b: Uint8Array, i: number) => b[i] | (b[i + 1] << 8);
const u32be = (b: Uint8Array, i: number) =>
  ((b[i] << 24) >>> 0) + ((b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]);
const ascii = (b: Uint8Array, i: number, s: string) =>
  i + s.length <= b.length && [...s].every((c, k) => b[i + k] === c.charCodeAt(0));

/// Reads JPEG (SOFn + APP1 Exif orientation), PNG (IHDR) and WebP (VP8, VP8L,
/// VP8X) headers from the first bytes of a file. Anything else is `null`: the
/// picture is then decoded without a size known in advance (GIF, BMP, AVIF,
/// HEIC on Safari). `complete` says the bytes are the whole file; when they are
/// not and a JPEG's frame header lies further on, the answer is `NEED_MORE`.
export function parseImageHeader(
  b: Uint8Array,
  complete = true,
): ImageHeader | null | typeof NEED_MORE {
  if (b.length >= 24 && u32be(b, 0) === 0x89504e47 && u32be(b, 4) === 0x0d0a1a0a) {
    if (!ascii(b, 12, 'IHDR')) return null;
    return sized('png', u32be(b, 16), u32be(b, 20), 1);
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
  if (b.length < 2 || b[0] !== 0xff || b[1] !== 0xd8) return null;
  let i = 2;
  let orientation = 1;
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
    if (marker === 0xe1 && ascii(b, i + 4, 'Exif\0\0')) {
      if (end > b.length) return complete ? null : NEED_MORE;
      orientation = exifOrientation(b, i + 10, end);
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

/// The Orientation tag (0x0112) of IFD0, from the TIFF header at `t`.
function exifOrientation(b: Uint8Array, t: number, end: number): number {
  if (t + 8 > end) return 1;
  const little = b[t] === 0x49 && b[t + 1] === 0x49;
  if (!little && !(b[t] === 0x4d && b[t + 1] === 0x4d)) return 1;
  const r16 = (i: number) => (little ? u16le(b, i) : u16be(b, i));
  const r32 = (i: number) =>
    little ? (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)) >>> 0 : u32be(b, i);
  if (r16(t + 2) !== 42) return 1;
  const ifd = t + r32(t + 4);
  if (ifd + 2 > end) return 1;
  const count = r16(ifd);
  for (let k = 0; k < count; k++) {
    const e = ifd + 2 + k * 12;
    if (e + 12 > end) return 1;
    if (r16(e) === 0x0112) {
      const value = r16(e + 8);
      return value >= 1 && value <= 8 ? value : 1;
    }
  }
  return 1;
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
/// to 4 MiB when a JPEG's APP segments are long). `null` when unknown.
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

/// A decoded picture, ready to draw. `width` × `height` is the size it draws
/// at with no matrix; `orientation` is what is still to apply (1 = none).
export type DecodedImage = {
  source: CanvasImageSource;
  width: number;
  height: number;
  orientation: number;
  release: () => void;
};

export type PrepareFailure = 'unreadable' | 'too_large' | 'failed';

export type PrepareResult =
  | { ok: true; blob: Blob; width: number; height: number; pixels: number | null }
  | { ok: false; reason: PrepareFailure; pixels: number | null };

/// The seams — the app's `ImageCompressor` idea: the flow is unit-testable
/// without a canvas (jsdom has none); the defaults are the browser's.
export type CompressDeps = {
  probe?: (file: Blob) => Promise<ImageHeader | null>;
  decode?: (file: Blob, header: ImageHeader | null, target: Size | null) => Promise<DecodedImage>;
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
  let pixels = header ? header.width * header.height : null;
  if (pixels !== null && pixels > UPLOAD_RULE.maxInputPixels) {
    return { ok: false, reason: 'too_large', pixels };
  }
  const shown = header ? orientedSize(header) : null;
  const planned = shown ? targetSize(shown.width, shown.height) : null;

  let image: DecodedImage;
  try {
    image = await deps.decode(file, header, planned);
  } catch {
    return { ok: false, reason: 'unreadable', pixels };
  }
  pixels ??= image.width * image.height;
  const target = planned ?? targetSize(image.width, image.height);
  let blob: Blob | null = null;
  try {
    blob = await deps.encode(image, target);
  } catch {
    blob = null;
  } finally {
    image.release();
  }
  if (!blob) return { ok: false, reason: 'failed', pixels };
  if (blob.size > deps.maxBytes) return { ok: false, reason: 'too_large', pixels };
  return { ok: true, blob, width: target.width, height: target.height, pixels };
}

let queue: Promise<unknown> = Promise.resolve();

/// Prepares one picked picture for upload. **One at a time**: « Avant » and
/// « Après » picked back to back would otherwise decode together and double
/// the memory peak on a phone. Never throws.
export function compressForUpload(file: Blob, deps: CompressDeps = {}): Promise<PrepareResult> {
  const all: Required<CompressDeps> = {
    probe: deps.probe ?? probeImageHeader,
    decode: deps.decode ?? decodeInBrowser,
    encode: deps.encode ?? encodeOnWhite,
    maxBytes: deps.maxBytes ?? UPLOAD_RULE.maxBytes,
  };
  const run = queue.then(() =>
    prepare(file, all).catch((): PrepareResult => ({ ok: false, reason: 'failed', pixels: null })),
  );
  queue = run;
  return run;
}

// ─── The browser implementation ─────────────────────────────────────────────

/// 2 × 1 grey JPEG tagged EXIF orientation 6 (177 bytes): an engine that
/// applies EXIF orientation decodes it 1 × 2.
const ORIENTED_PROBE =
  '/9j/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAYAAAAAAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/wAALCAABAAIBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAAAP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AP//Z';

type DecodePath = 'bitmap' | 'img' | 'manual';
let decodePath: Promise<DecodePath> | null = null;

/// Which decoder applies EXIF orientation, checked once: `createImageBitmap`
/// (asks the decoder for the target size), else `<img>` (CSS
/// `image-orientation: from-image`), else rotate on the canvas ourselves.
function detectDecodePath(): Promise<DecodePath> {
  decodePath ??= (async (): Promise<DecodePath> => {
    const bytes = Uint8Array.from(atob(ORIENTED_PROBE), (c) => c.charCodeAt(0));
    const probe = new Blob([bytes], { type: 'image/jpeg' });
    if (typeof createImageBitmap === 'function') {
      try {
        const bitmap = await createImageBitmap(probe, { imageOrientation: 'from-image' });
        const upright = bitmap.width === 1 && bitmap.height === 2;
        bitmap.close();
        if (upright) return 'bitmap';
      } catch {
        // fall through to <img>
      }
    }
    try {
      const img = await loadImage(probe);
      const upright = img.el.naturalWidth === 1 && img.el.naturalHeight === 2;
      img.revoke();
      if (upright) return 'img';
    } catch {
      // last resort below
    }
    return 'manual';
  })();
  return decodePath;
}

async function loadImage(file: Blob): Promise<{ el: HTMLImageElement; revoke: () => void }> {
  const url = URL.createObjectURL(file);
  const el = new Image();
  el.decoding = 'async';
  el.src = url;
  try {
    await el.decode();
  } catch (error) {
    URL.revokeObjectURL(url);
    throw error;
  }
  return { el, revoke: () => URL.revokeObjectURL(url) };
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

/// Decodes AT THE TARGET SIZE when the header gave one — about half the memory
/// peak of a full-size decode (measured, spec §5.3) — and never allocates a
/// canvas at the source size.
async function decodeInBrowser(
  file: Blob,
  header: ImageHeader | null,
  target: Size | null,
): Promise<DecodedImage> {
  const path = await detectDecodePath();
  if (path === 'bitmap') {
    if (target) {
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
    }
    return fromBitmap(await createImageBitmap(file, { imageOrientation: 'from-image' }));
  }
  const img = await loadImage(file);
  const orientation = path === 'manual' ? (header?.orientation ?? 1) : 1;
  const quarter = orientation >= 5 && orientation <= 8;
  const { naturalWidth: w, naturalHeight: h } = img.el;
  return {
    source: img.el,
    width: quarter ? h : w,
    height: quarter ? w : h,
    orientation,
    release: img.revoke,
  };
}

type AnyCanvas = OffscreenCanvas | HTMLCanvasElement;

function makeCanvas(width: number, height: number): AnyCanvas {
  if (typeof OffscreenCanvas === 'function') return new OffscreenCanvas(width, height);
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  return canvas;
}

function toJpeg(canvas: AnyCanvas, quality: number): Promise<Blob | null> {
  if ('convertToBlob' in canvas) return canvas.convertToBlob({ type: 'image/jpeg', quality });
  return new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality));
}

/// Draws on white — a transparent pixel would otherwise become BLACK in a
/// JPEG (measured) — then encodes JPEG at the app's quality. A canvas encode
/// writes no EXIF: the metadata (GPS included) goes by construction.
async function encodeOnWhite(image: DecodedImage, target: Size): Promise<Blob | null> {
  const { width, height } = target;
  const canvas = makeCanvas(width, height);
  const ctx = canvas.getContext('2d') as
    | CanvasRenderingContext2D
    | OffscreenCanvasRenderingContext2D
    | null;
  if (!ctx) return null;
  ctx.fillStyle = colors.secondary;
  ctx.fillRect(0, 0, width, height);
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  const t = orientationTransform(image.orientation, width, height);
  ctx.setTransform(t.a, t.b, t.c, t.d, t.e, t.f);
  ctx.drawImage(image.source, 0, 0, t.drawWidth, t.drawHeight);
  return toJpeg(canvas, UPLOAD_RULE.quality);
}

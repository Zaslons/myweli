import { type APIRequestContext, type Page, expect, test } from '@playwright/test';

import { signInPro } from './_auth';
import {
  exifApp1,
  headerOnlyJpeg,
  ijgLumaTable,
  inspectJpeg,
  type JpegInspection,
  orientationApp1,
  orientationTiff,
  spliceAfterFrameHeader,
  spliceAfterSoi,
} from './_jpeg.mjs';
import { serveStubImages } from './_pixel';

/// docs/design/web-pro-upload-resize.md §8.2 (decision 107) — a Pro photo
/// uploaded from the website is the file the app would have uploaded: short
/// side ≤ 1600, long side ≤ 2400, never enlarged, JPEG at quality 80, the
/// camera's orientation in the pixels, no metadata, transparency on white.
///
/// Real Chromium decodes and encodes here — jsdom cannot. Every fixture is
/// drawn by the test (gradients, stripes and two coloured squares; no photo,
/// no face, nothing downloaded), and the stub records what storage received
/// (`GET /__stub/uploads`), read with the same `inspectJpeg` the test first
/// runs on its own fixture as the control.

const STUB = `http://127.0.0.1:${process.env.STUB_PORT ?? '8787'}`;
const UNREADABLE = 'Cette image n’a pas pu être lue. Choisissez une image JPEG, PNG ou WebP.';
const TOO_LARGE = 'Cette image est trop grande pour être préparée ici. Choisissez une image plus petite.';
const BLOCKED = 'Votre navigateur empêche de préparer cette image. Essayez avec un autre navigateur.';

type Recorded = JpegInspection & {
  method: string;
  contentType: string | null;
  length: number;
  base64: string;
};

/// Every presign THIS page asked for: what it sent, what came back. Page-local
/// on purpose — another spec file may be uploading on the same stub.
type Sign = { body: { contentType: string; purpose: string }; uploadUrl: string | null };
/// Recorded when the request LEAVES (so « no sign » cannot pass because an
/// answer was still on its way); the answer's `uploadUrl` is filled in later.
function watchSigns(page: Page): Sign[] {
  const signs: Sign[] = [];
  page.on('request', (req) => {
    if (!req.url().endsWith('/api/pro/uploads/sign')) return;
    const entry: Sign = { body: req.postDataJSON(), uploadUrl: null };
    signs.push(entry);
    void req
      .response()
      .then((res) => res?.json())
      .then((json: { uploadUrl?: string } | undefined) => {
        entry.uploadUrl = json?.uploadUrl ?? null;
      })
      .catch(() => {});
  });
  return signs;
}

/// What storage received for the object that sign was for.
async function received(request: APIRequestContext, sign: Sign | undefined): Promise<Recorded> {
  expect(sign, 'no presign was asked for').toBeTruthy();
  await expect.poll(() => sign!.uploadUrl, { message: 'the presign never answered' }).toBeTruthy();
  const key = new URL(sign!.uploadUrl!).pathname.replace(/^\/r2-upload\//, '');
  const res = await request.get(`${STUB}/__stub/uploads?key=${encodeURIComponent(key)}`);
  expect(res.status(), `storage received nothing for ${key}`).toBe(200);
  return (await res.json()) as Recorded;
}

/// Nothing leaves the machine: every request to a host other than this one is
/// aborted, and a popup is closed.
test.beforeEach(async ({ context, page }) => {
  await context.route(
    (url) => url.hostname !== '127.0.0.1' && url.hostname !== 'localhost',
    (route) => route.abort(),
  );
  context.on('page', (p) => {
    if (p !== page) void p.close();
  });
  await serveStubImages(page);
});

/// A camera-sized JPEG, STORED landscape, drawn for EXIF orientation 6: blue
/// square at the stored top-left, red at the stored bottom-left — so the
/// picture shown upright has red top-left and blue top-right.
async function sidewaysPhoto(page: Page, width: number, height: number): Promise<Buffer> {
  const b64 = await page.evaluate(
    async ([w, h]) => {
      const c = new OffscreenCanvas(w, h);
      const g = c.getContext('2d')!;
      const grad = g.createLinearGradient(0, 0, w, h);
      grad.addColorStop(0, 'rgb(40, 120, 90)');
      grad.addColorStop(1, 'rgb(200, 210, 120)');
      g.fillStyle = grad;
      g.fillRect(0, 0, w, h);
      g.strokeStyle = 'rgba(30, 30, 30, 0.35)';
      g.lineWidth = 6;
      for (let x = -h; x < w; x += 48) {
        g.beginPath();
        g.moveTo(x, 0);
        g.lineTo(x + h, h);
        g.stroke();
      }
      const side = Math.round(h * 0.23);
      g.fillStyle = 'rgb(0, 0, 255)';
      g.fillRect(0, 0, side, side);
      g.fillStyle = 'rgb(255, 0, 0)';
      g.fillRect(0, h - side, side, side);
      const blob = await c.convertToBlob({ type: 'image/jpeg', quality: 0.92 });
      const bytes = new Uint8Array(await blob.arrayBuffer());
      let s = '';
      for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      return btoa(s);
    },
    [width, height] as const,
  );
  return Buffer.from(b64, 'base64');
}

/// A plain picture in any format the canvas encodes (no EXIF).
async function plainPicture(page: Page, width: number, height: number, type: string, alpha = false): Promise<Buffer> {
  const b64 = await page.evaluate(
    async ([w, h, t, transparent]) => {
      const c = new OffscreenCanvas(w, h);
      const g = c.getContext('2d')!;
      if (!transparent) {
        g.fillStyle = 'rgb(90, 140, 200)';
        g.fillRect(0, 0, w, h);
      }
      // A thick dark ring in the middle; with `transparent`, everything else
      // (the corners included) stays alpha 0 — a logo.
      g.strokeStyle = 'rgb(20, 20, 60)';
      g.lineWidth = Math.round(Math.min(w, h) * 0.12);
      g.beginPath();
      g.arc(w / 2, h / 2, Math.min(w, h) * 0.3, 0, Math.PI * 2);
      g.stroke();
      const blob = await c.convertToBlob({ type: t });
      const bytes = new Uint8Array(await blob.arrayBuffer());
      let s = '';
      for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      return btoa(s);
    },
    [width, height, type, alpha] as const,
  );
  return Buffer.from(b64, 'base64');
}

/// Decodes recorded bytes in the page (via `<img>`, which works with or
/// without `createImageBitmap`) and samples pixels 60 px in from each corner.
async function corners(page: Page, bytes: Buffer, mime = 'image/jpeg') {
  return page.evaluate(
    async ([b64, type]) => {
      const bin = atob(b64);
      const u8 = Uint8Array.from(bin, (ch) => ch.charCodeAt(0));
      const url = URL.createObjectURL(new Blob([u8], { type }));
      const img = new Image();
      img.src = url;
      await img.decode();
      const c = document.createElement('canvas');
      c.width = img.naturalWidth;
      c.height = img.naturalHeight;
      const g = c.getContext('2d', { willReadFrequently: true })!;
      g.drawImage(img, 0, 0);
      URL.revokeObjectURL(url);
      const at = (x: number, y: number) => Array.from(g.getImageData(x, y, 1, 1).data);
      const w = c.width;
      const h = c.height;
      const d = Math.min(60, Math.floor(Math.min(w, h) / 4));
      return {
        size: [w, h],
        topLeft: at(d, d),
        topRight: at(w - 1 - d, d),
        bottomLeft: at(d, h - 1 - d),
        bottomRight: at(w - 1 - d, h - 1 - d),
        centreTop: at(Math.floor(w / 2), Math.floor(h * 0.2)),
      };
    },
    [bytes.toString('base64'), mime] as const,
  );
}

/// How a picture LOOKS as the browser shows it (orientation applied): the
/// mean colour of a small square at five places given as fractions of the
/// size — near each corner and at the centre. Run on the input it is the
/// control; run on the upload, the two must agree, so a picture squeezed,
/// sideways, or not filling its frame (white where the photo should be) is
/// caught whatever the fixture's colours are.
async function look(page: Page, bytes: Buffer, mime = 'image/jpeg') {
  return page.evaluate(
    async ([b64, type]) => {
      const u8 = Uint8Array.from(atob(b64), (ch) => ch.charCodeAt(0));
      const url = URL.createObjectURL(new Blob([u8], { type }));
      const img = new Image();
      img.src = url;
      await img.decode();
      const w = img.naturalWidth;
      const h = img.naturalHeight;
      const c = document.createElement('canvas');
      c.width = w;
      c.height = h;
      const g = c.getContext('2d', { willReadFrequently: true })!;
      g.drawImage(img, 0, 0);
      URL.revokeObjectURL(url);
      const r = Math.max(2, Math.round(Math.min(w, h) * 0.006));
      const mean = (fx: number, fy: number) => {
        const x = Math.round(fx * (w - 1));
        const y = Math.round(fy * (h - 1));
        const d = g.getImageData(x - r, y - r, 2 * r + 1, 2 * r + 1).data;
        const sum = [0, 0, 0];
        for (let i = 0; i < d.length; i += 4) for (let k = 0; k < 3; k++) sum[k] += d[i + k];
        return sum.map((v) => Math.round(v / (d.length / 4)));
      };
      return {
        size: [w, h],
        at: {
          topLeft: mean(0.06, 0.06),
          topRight: mean(0.94, 0.06),
          bottomLeft: mean(0.06, 0.94),
          bottomRight: mean(0.94, 0.94),
          centre: mean(0.5, 0.5),
        },
      };
    },
    [bytes.toString('base64'), mime] as const,
  );
}

/// The upload looks like the input as the browser shows it, place by place.
function expectLooksLike(
  out: Awaited<ReturnType<typeof look>>,
  input: Awaited<ReturnType<typeof look>>,
  tolerance = 28,
) {
  for (const place of Object.keys(input.at) as (keyof typeof input.at)[]) {
    const diff = Math.max(...out.at[place].map((v, k) => Math.abs(v - input.at[place][k])));
    expect(diff, `${place}: upload ${out.at[place]} vs input ${input.at[place]}`).toBeLessThanOrEqual(tolerance);
  }
}

const isRed = ([r, g, b]: number[]) => r > 200 && g < 70 && b < 70;
const isBlue = ([r, g, b]: number[]) => b > 200 && r < 70 && g < 70;
const isWhite = ([r, g, b]: number[]) => r >= 245 && g >= 245 && b >= 245;
const isNeither = (p: number[]) => !isRed(p) && !isBlue(p);

/// What a correctly prepared upload looks like on the wire.
function expectPrepared(last: Recorded, width: number, height: number) {
  expect(last).toMatchObject({
    method: 'PUT',
    contentType: 'image/jpeg',
    jpeg: true,
    width,
    height,
    exif: false,
    makeMarker: false,
    gpsMarker: false,
  });
  // JPEG quality 80 — Chromium's encoder writes libjpeg's IJG-scaled table.
  expect(last.lumaTable).toEqual(ijgLumaTable(80));
  expect(last.length).toBeLessThanOrEqual(5 * 1024 * 1024);
}

/// Médias saves each gesture at once; here the save is answered in the
/// browser so the shared stub's seeded gallery stays as other spec files
/// expect it. The sign and the PUT still go to the stub.
async function openMedias(page: Page) {
  await page.route('**/api/pro/medias/gallery', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: '{}' }),
  );
  await signInPro(page);
  await page.goto('/pro/medias');
  await expect(page.getByRole('heading', { name: 'Médias' })).toBeVisible();
  await expect(page.locator('main img').first()).toBeVisible();
}

test('Médias: a sideways 12 MP camera JPEG with GPS → an upright 1600×2133 JPEG at q80, no metadata', async ({
  page,
  request,
}) => {
  await openMedias(page);
  const signs = watchSigns(page);
  const photos = page.locator('main img');
  const shown = await photos.count();

  const input = spliceAfterSoi(await sidewaysPhoto(page, 4032, 3024), exifApp1({ orientation: 6 }));
  // The control: the same reader sees everything the fixture carries.
  expect(inspectJpeg(input)).toMatchObject({
    width: 4032,
    height: 3024,
    exif: true,
    makeMarker: true,
    gpsMarker: true,
  });

  await page
    .locator('input[type=file]')
    .first()
    .setInputFiles({ name: 'IMG_0042.jpg', mimeType: 'image/jpeg', buffer: input });
  await expect(photos).toHaveCount(shown + 1);

  expect(signs.map((x) => x.body)).toEqual([{ contentType: 'image/jpeg', purpose: 'gallery' }]);
  const last = await received(request, signs[0]);
  expectPrepared(last, 1600, 2133);
  expect(last.length).toBeLessThan(input.length);
  const px = await corners(page, Buffer.from(last.base64, 'base64'));
  expect(px.size).toEqual([1600, 2133]);
  // Upright: red top-left, blue top-right, neither at the bottom.
  expect(isRed(px.topLeft), `top-left ${px.topLeft}`).toBe(true);
  expect(isBlue(px.topRight), `top-right ${px.topRight}`).toBe(true);
  expect(isNeither(px.bottomLeft) && isNeither(px.bottomRight)).toBe(true);
  // …and everywhere else as the browser shows the input — the photo fills its
  // frame to the bottom corners (a draw that stopped short left them white,
  // and the checks above stayed green: the review's E3).
  expectLooksLike(await look(page, Buffer.from(last.base64, 'base64')), await look(page, input));
});

test('Médias, without createImageBitmap: the <img> path gives the same upright file', async ({
  page,
  request,
}) => {
  await page.addInitScript(() => {
    Object.defineProperty(window, 'createImageBitmap', { value: undefined, configurable: true, writable: true });
  });
  await openMedias(page);
  const signs = watchSigns(page);
  expect(await page.evaluate(() => typeof createImageBitmap)).toBe('undefined');
  const photos = page.locator('main img');
  const shown = await photos.count();
  const input = spliceAfterSoi(await sidewaysPhoto(page, 4032, 3024), exifApp1({ orientation: 6 }));

  await page
    .locator('input[type=file]')
    .first()
    .setInputFiles({ name: 'IMG_0044.jpg', mimeType: 'image/jpeg', buffer: input });
  await expect(photos).toHaveCount(shown + 1);

  const last = await received(request, signs[0]);
  expectPrepared(last, 1600, 2133);
  const px = await corners(page, Buffer.from(last.base64, 'base64'));
  expect(isRed(px.topLeft), `top-left ${px.topLeft}`).toBe(true);
  expect(isBlue(px.topRight), `top-right ${px.topRight}`).toBe(true);
  expectLooksLike(await look(page, Buffer.from(last.base64, 'base64')), await look(page, input));
});

test('Médias: a file the browser cannot read says so, and spends no signature', async ({ page }) => {
  await openMedias(page);
  const signs = watchSigns(page);
  const photos = page.locator('main img');
  const shown = await photos.count();
  // A HEIC from a computer, as Chrome sees it: bytes it cannot decode.
  const noise = Buffer.from(Array.from({ length: 4096 }, (_, i) => (i * 73 + 41) % 256));

  await page
    .locator('input[type=file]')
    .first()
    .setInputFiles({ name: 'IMG_0043.heic', mimeType: 'image/heic', buffer: noise });
  // The toast region (the Pro shell has other live regions too).
  await expect(page.getByRole('status').filter({ hasText: UNREADABLE })).toBeVisible();

  expect(signs).toEqual([]);
  await expect(photos).toHaveCount(shown);
});

test('Avant / Après: a picture over 64 MP is refused before decoding; a 3000×2000 one goes as 2400×1600', async ({
  page,
  request,
}) => {
  await openMedias(page);
  const signs = watchSigns(page);
  await page.getByRole('button', { name: 'Avant / Après' }).click();

  // A header announcing 12000×9000 (108 MP) and no pixel at all: only a check
  // made BEFORE decoding can answer « trop grande »; a decoder would say
  // « pas pu être lue ».
  const huge = headerOnlyJpeg(12000, 9000);
  expect(inspectJpeg(huge)).toMatchObject({ width: 12000, height: 9000 });
  const pickBefore = page.locator('label', { hasText: /^Avant/ }).locator('input[type=file]');
  await pickBefore.setInputFiles({ name: 'avant.jpg', mimeType: 'image/jpeg', buffer: huge });
  // The toast region (the Pro shell has other live regions too).
  await expect(page.getByRole('status').filter({ hasText: TOO_LARGE })).toBeVisible();
  expect(signs).toEqual([]);

  const wide = await plainPicture(page, 3000, 2000, 'image/jpeg');
  await pickBefore.setInputFiles({ name: 'avant.jpg', mimeType: 'image/jpeg', buffer: wide });
  await expect(page.locator('label', { hasText: 'Avant ✓' })).toBeVisible();
  expect(signs.map((x) => x.body)).toEqual([{ contentType: 'image/jpeg', purpose: 'gallery' }]);
  expectPrepared(await received(request, signs[0]), 2400, 1600);
});

test('Profil: a transparent PNG logo → a JPEG on white, at its own size, signed as JPEG', async ({
  page,
  request,
}) => {
  await signInPro(page);
  await page.goto('/pro/profil');
  await expect(page.getByLabel('Nom du salon')).toBeVisible();
  const signs = watchSigns(page);
  const png = await plainPicture(page, 1200, 1200, 'image/png', true);
  // The control: the fixture's corner really is transparent.
  const raw = await corners(page, png, 'image/png');
  expect(raw.topLeft[3]).toBe(0);

  await page.getByLabel('Logo du salon').setInputFiles({ name: 'logo.png', mimeType: 'image/png', buffer: png });
  await expect(page.getByRole('button', { name: 'Changer le logo' })).toBeVisible();

  expect(signs.map((x) => x.body)).toEqual([{ contentType: 'image/jpeg', purpose: 'logo' }]);
  const last = await received(request, signs[0]);
  // 1200×1200 is inside the rule: re-encoded, never enlarged.
  expectPrepared(last, 1200, 1200);
  const px = await corners(page, Buffer.from(last.base64, 'base64'));
  for (const corner of [px.topLeft, px.topRight, px.bottomLeft, px.bottomRight]) {
    expect(isWhite(corner), `corner ${corner}`).toBe(true);
  }
  // …and the ring is still there.
  expect(px.centreTop.slice(0, 3).every((v) => v < 90), `ring ${px.centreTop}`).toBe(true);
});

test('Catalogue → Employés: an unreadable « PNG » says so; a 600×800 PNG goes as a 600×800 JPEG', async ({
  page,
  request,
}) => {
  await signInPro(page);
  await page.goto('/pro/catalogue');
  await page.getByRole('button', { name: 'Employés' }).click();
  await page.getByRole('button', { name: 'Ajouter un employé' }).click();
  const input = page.getByLabel('Photo de l’employé');
  const signs = watchSigns(page);

  await input.setInputFiles({ name: 'photo.png', mimeType: 'image/png', buffer: Buffer.from('not a picture at all') });
  await expect(page.getByRole('alert').filter({ hasText: UNREADABLE })).toBeVisible();
  expect(signs).toEqual([]);

  const small = await plainPicture(page, 600, 800, 'image/png');
  await input.setInputFiles({ name: 'portrait.png', mimeType: 'image/png', buffer: small });
  await expect(page.getByRole('button', { name: 'Changer la photo' })).toBeVisible();
  expect(signs.map((x) => x.body)).toEqual([{ contentType: 'image/jpeg', purpose: 'gallery' }]);
  expectPrepared(await received(request, signs[0]), 600, 800);
});

// ─── The review of 2026-11-09 (web-pro-upload-resize.md §13.5) ────────────────

// F7: the engine check used to decode its probe at its own size only. An
// engine that drops the EXIF orientation when it is asked for a size would
// pass it and send every sideways photo sideways. Simulated: whenever a size
// is asked for, the Exif segment is removed before Chromium decodes. The
// check now decodes its probe AT A SIZE and reads its pixels, so this engine
// is sent down the <img> path — and the photo comes out upright.
test('an engine that drops the orientation when it scales is not trusted: the photo is still upright', async ({
  page,
  request,
}) => {
  await page.addInitScript(() => {
    const native = window.createImageBitmap.bind(window);
    const withoutExif = (b: Uint8Array) => {
      if (b[0] !== 0xff || b[1] !== 0xd8) return b;
      const parts: Uint8Array[] = [b.subarray(0, 2)];
      let i = 2;
      while (i + 4 <= b.length && b[i] === 0xff && b[i + 1] !== 0xda) {
        const end = i + 2 + ((b[i + 2] << 8) | b[i + 3]);
        const exif = b[i + 1] === 0xe1 && String.fromCharCode(...b.subarray(i + 4, i + 8)) === 'Exif';
        if (!exif) parts.push(b.subarray(i, end));
        i = end;
      }
      parts.push(b.subarray(i));
      const out = new Uint8Array(parts.reduce((n, x) => n + x.length, 0));
      let o = 0;
      for (const x of parts) {
        out.set(x, o);
        o += x.length;
      }
      return out;
    };
    window.createImageBitmap = (async (source: ImageBitmapSource, options?: ImageBitmapOptions) => {
      if (source instanceof Blob && options && options.resizeWidth !== undefined) {
        const bytes = withoutExif(new Uint8Array(await source.arrayBuffer()));
        return native(new Blob([bytes as BlobPart], { type: source.type }), options);
      }
      return options ? native(source, options) : native(source);
    }) as typeof createImageBitmap;
  });
  await openMedias(page);
  const signs = watchSigns(page);
  const photos = page.locator('main img');
  const shown = await photos.count();
  const input = spliceAfterSoi(await sidewaysPhoto(page, 4032, 3024), exifApp1({ orientation: 6 }));
  // The control: in this page, a bitmap asked for a size really is sideways.
  const sideways = await page.evaluate(async (b64) => {
    const blob = new Blob([Uint8Array.from(atob(b64), (ch) => ch.charCodeAt(0))], { type: 'image/jpeg' });
    const bitmap = await createImageBitmap(blob, { imageOrientation: 'from-image', resizeWidth: 1600, resizeHeight: 2133 });
    const c = new OffscreenCanvas(1600, 2133);
    const g = c.getContext('2d')!;
    g.drawImage(bitmap, 0, 0);
    return Array.from(g.getImageData(60, 60, 1, 1).data);
  }, input.toString('base64'));
  expect(isBlue(sideways), `the simulated engine's top-left ${sideways}`).toBe(true);

  await page.locator('input[type=file]').first().setInputFiles({ name: 'IMG_0045.jpg', mimeType: 'image/jpeg', buffer: input });
  await expect(photos).toHaveCount(shown + 1);
  const last = await received(request, signs[0]);
  expectPrepared(last, 1600, 2133);
  const px = await corners(page, Buffer.from(last.base64, 'base64'));
  expect(isRed(px.topLeft), `top-left ${px.topLeft}`).toBe(true);
  expect(isBlue(px.topRight), `top-right ${px.topRight}`).toBe(true);
  expectLooksLike(await look(page, Buffer.from(last.base64, 'base64')), await look(page, input));
});

/// Four flat quadrants — red, green / blue, yellow — STORED 3000 × 2000.
async function quadrants(page: Page, type: 'image/jpeg' | 'image/png'): Promise<Buffer> {
  const b64 = await page.evaluate(async (t) => {
    const c = new OffscreenCanvas(3000, 2000);
    const g = c.getContext('2d')!;
    const fills: [string, number, number][] = [
      ['rgb(255, 0, 0)', 0, 0],
      ['rgb(0, 200, 0)', 1500, 0],
      ['rgb(0, 0, 255)', 0, 1000],
      ['rgb(255, 230, 0)', 1500, 1000],
    ];
    for (const [fill, x, y] of fills) {
      g.fillStyle = fill;
      g.fillRect(x, y, 1500, 1000);
    }
    const bytes = new Uint8Array(await (await c.convertToBlob({ type: t, quality: 0.92 })).arrayBuffer());
    let s = '';
    for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    return btoa(s);
  }, type);
  return Buffer.from(b64, 'base64');
}

const CRC = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc32 = (b: Buffer) => {
  let c = 0xffffffff;
  for (const x of b) c = CRC[(c ^ x) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
/// `png` with a chunk inserted right after IHDR — before the image data.
function pngWithChunk(png: Buffer, type: string, data: Buffer): Buffer {
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const head = Buffer.alloc(4);
  head.writeUInt32BE(data.length);
  const tail = Buffer.alloc(4);
  tail.writeUInt32BE(crc32(body));
  const ihdrEnd = 8 + 8 + 13 + 4;
  return Buffer.concat([png.subarray(0, ihdrEnd), head, body, tail, png.subarray(ihdrEnd)]);
}

/// The browser's own view of a file: `<img>` once loaded, and
/// `createImageBitmap` with the orientation applied — the control.
async function shownSize(page: Page, bytes: Buffer, mime: string) {
  return page.evaluate(
    async ([b64, type]) => {
      const blob = new Blob([Uint8Array.from(atob(b64), (ch) => ch.charCodeAt(0))], { type });
      const url = URL.createObjectURL(blob);
      const img = new Image();
      await new Promise((ok, ko) => {
        img.onload = ok;
        img.onerror = ko;
        img.src = url;
      });
      URL.revokeObjectURL(url);
      const bitmap = await createImageBitmap(blob, { imageOrientation: 'from-image' });
      const both = { img: [img.naturalWidth, img.naturalHeight], bitmap: [bitmap.width, bitmap.height] };
      bitmap.close();
      return both;
    },
    [bytes.toString('base64'), mime] as const,
  );
}

/// The rule, for the expected sizes (the unit tests pin it on its own).
function rule(width: number, height: number): [number, number] {
  let long = Math.max(width, height);
  let short = Math.min(width, height);
  if (long > 2400) {
    short = Math.round((short * 2400) / long);
    long = 2400;
  }
  if (short > 1600) {
    long = Math.floor((long * 1600) / short);
    short = 1600;
  }
  return width >= height ? [long, short] : [short, long];
}

// F1: wherever our header reading and the browser's differ, the BROWSER
// decodes — sizing the target from our reading squeezed the picture into the
// other orientation's frame (measured by the review on the first four rows).
// The last row is the one our reader cannot see at all: an Exif segment after
// the frame header, which Chromium reads — only the browser's own reading of
// the size can get it right.
test('the browser’s reading of the orientation sizes the upload: odd Exif layouts are never squeezed', async ({
  page,
  request,
}) => {
  test.setTimeout(90_000);
  await openMedias(page);
  const jpeg = await quadrants(page, 'image/jpeg');
  const png = await quadrants(page, 'image/png');
  const cases: { name: string; mime: string; buffer: Buffer; shown: [number, number] }[] = [
    { name: 'two Exif segments, 6 then 1', mime: 'image/jpeg', buffer: spliceAfterSoi(jpeg, Buffer.concat([orientationApp1(6), orientationApp1(1)])), shown: [2000, 3000] },
    { name: 'two Exif segments, 1 then 6', mime: 'image/jpeg', buffer: spliceAfterSoi(jpeg, Buffer.concat([orientationApp1(1), orientationApp1(6)])), shown: [3000, 2000] },
    { name: 'Orientation stored as a LONG 6', mime: 'image/jpeg', buffer: spliceAfterSoi(jpeg, orientationApp1(6, { type: 4 })), shown: [3000, 2000] },
    { name: 'PNG eXIf 6 before the image data', mime: 'image/png', buffer: pngWithChunk(png, 'eXIf', orientationTiff(6)), shown: [2000, 3000] },
    { name: 'Exif 6 after the frame header', mime: 'image/jpeg', buffer: spliceAfterFrameHeader(jpeg, orientationApp1(6)), shown: [2000, 3000] },
  ];
  const photos = page.locator('main img');
  for (const c of cases) {
    // The control: this browser shows the fixture as the row says, both ways.
    expect(await shownSize(page, c.buffer, c.mime), c.name).toEqual({ img: c.shown, bitmap: c.shown });
    const signs = watchSigns(page);
    const shown = await photos.count();
    await page.locator('input[type=file]').first().setInputFiles({ name: 'odd', mimeType: c.mime, buffer: c.buffer });
    await expect(photos, c.name).toHaveCount(shown + 1);
    const last = await received(request, signs[0]);
    const [w, h] = rule(...c.shown);
    expect([last.width, last.height], c.name).toEqual([w, h]);
    expectLooksLike(await look(page, Buffer.from(last.base64, 'base64')), await look(page, c.buffer, c.mime), 28);
  }
});

// F2: GIF, BMP and AVIF had no size read, so the 64 MP ceiling never applied
// to them: a 72 MP GIF or AVIF was decoded whole (~288 MB of pixels). Headers
// only, no pixel: only a check made BEFORE decoding can answer « trop grande »
// — a decoder would say « pas pu être lue ».
test('GIF, BMP and AVIF over 64 MP are refused before decoding too', async ({ page }) => {
  await openMedias(page);
  const signs = watchSigns(page);
  const le16 = (n: number) => [n & 0xff, (n >> 8) & 0xff];
  const le32 = (n: number) => [n & 0xff, (n >>> 8) & 0xff, (n >>> 16) & 0xff, (n >>> 24) & 0xff];
  const be32 = (n: number) => [(n >>> 24) & 0xff, (n >>> 16) & 0xff, (n >>> 8) & 0xff, n & 0xff];
  const text = (t: string) => [...Buffer.from(t, 'latin1')];
  const box = (type: string, body: number[]) => [...be32(8 + body.length), ...text(type), ...body];
  const full = (type: string, body: number[]) => box(type, [0, 0, 0, 0, ...body]);
  const files = [
    { name: 'a.gif', mimeType: 'image/gif', buffer: Buffer.from([...text('GIF89a'), ...le16(9000), ...le16(8000), 0, 0, 0, 0x3b]) },
    { name: 'a.bmp', mimeType: 'image/bmp', buffer: Buffer.from([...text('BM'), ...le32(0), 0, 0, 0, 0, ...le32(54), ...le32(40), ...le32(9000), ...le32(8000), 1, 0, 24, 0, ...new Array(24).fill(0)]) },
    {
      name: 'a.avif',
      mimeType: 'image/avif',
      buffer: Buffer.from([
        ...box('ftyp', [...text('avif'), 0, 0, 0, 0, ...text('mif1'), ...text('miaf')]),
        ...full('meta', [
          ...full('hdlr', [0, 0, 0, 0, ...text('pict'), ...new Array(13).fill(0)]),
          ...box('iprp', [...box('ipco', full('ispe', [...be32(9000), ...be32(8000)])), ...box('ipma', [0, 0, 0, 0])]),
        ]),
      ]),
    },
  ];
  for (const file of files) {
    await page.locator('input[type=file]').first().setInputFiles(file);
    await expect(page.getByRole('status').filter({ hasText: TOO_LARGE }), file.name).toBeVisible();
    await expect(page.getByText('Ajouter une photo')).toBeVisible();
  }
  expect(signs).toEqual([]);
});

/// Holds every presign until `release()`: the busy state lasts as long as the
/// test needs.
async function holdSigns(page: Page) {
  let release: () => void = () => {};
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route('**/api/pro/uploads/sign', async (route) => {
    await gate;
    await route.continue();
  });
  return release;
}

// F3: leaving Médias 41 ms after picking a photo still put it in the public
// gallery about 3 s later (measured by the review, with the decode slowed).
test('Médias left while a photo is prepared or signed: nothing is signed, sent or added', async ({ page }) => {
  // The decode at the target size is slowed (the engine checks are not).
  await page.addInitScript(() => {
    const native = window.createImageBitmap.bind(window);
    window.createImageBitmap = (async (...args: Parameters<typeof createImageBitmap>) => {
      const opts = args[args.length - 1] as ImageBitmapOptions | undefined;
      if (opts && typeof opts === 'object' && (opts.resizeWidth ?? 0) >= 100) {
        await new Promise((r) => setTimeout(r, 1500));
      }
      return native(...args);
    }) as typeof createImageBitmap;
  });
  let saves = 0;
  await page.route('**/api/pro/medias/gallery', (route) => {
    saves += 1;
    return route.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
  });
  const puts: string[] = [];
  page.on('request', (req) => {
    if (req.url().includes('/r2-upload/')) puts.push(req.url());
  });
  await signInPro(page);
  await page.goto('/pro/medias');
  await expect(page.locator('main img').first()).toBeVisible();
  const photo = await plainPicture(page, 3000, 2000, 'image/jpeg');

  // 1. Left while it is being prepared.
  const signs = watchSigns(page);
  await page.locator('input[type=file]').first().setInputFiles({ name: 'a.jpg', mimeType: 'image/jpeg', buffer: photo });
  await expect(page.getByText('Téléversement…')).toBeVisible();
  await page.getByRole('link', { name: 'Profil', exact: true }).first().click();
  await expect(page).toHaveURL(/\/pro\/profil$/);
  await page.waitForTimeout(2500);
  expect(signs).toEqual([]);
  expect(puts).toEqual([]);
  expect(saves).toBe(0);

  // 2. Left while the signature is out.
  await page.goto('/pro/medias');
  await expect(page.locator('main img').first()).toBeVisible();
  const release = await holdSigns(page);
  await page.locator('input[type=file]').first().setInputFiles({ name: 'b.jpg', mimeType: 'image/jpeg', buffer: photo });
  await expect.poll(() => signs.length, { timeout: 10_000 }).toBe(1);
  await page.getByRole('link', { name: 'Profil', exact: true }).first().click();
  await expect(page).toHaveURL(/\/pro\/profil$/);
  release();
  await expect.poll(() => signs[0].uploadUrl, { message: 'the held presign never answered' }).toBeTruthy();
  await page.waitForTimeout(800);
  expect(puts).toEqual([]);
  expect(saves).toBe(0);

  // 3. The control: the same photo, the page kept — signed, sent, saved.
  await page.goto('/pro/medias');
  await expect(page.locator('main img').first()).toBeVisible();
  const before = await page.locator('main img').count();
  await page.locator('input[type=file]').first().setInputFiles({ name: 'c.jpg', mimeType: 'image/jpeg', buffer: photo });
  await expect(page.locator('main img')).toHaveCount(before + 1, { timeout: 10_000 });
  expect(puts).toHaveLength(1);
  expect(saves).toBe(1);
});

// F4: a browser that blanks what a canvas gives back (Firefox's
// resistFingerprinting, Tor) would have sent a white picture with no error.
// Simulated here by painting every canvas white before it is encoded — AFTER
// the fixture is drawn, so only the app's canvases are affected.
test('a browser whose canvas comes back blank: the person is told, nothing is signed', async ({ page }) => {
  await openMedias(page);
  const signs = watchSigns(page);
  const photo = await plainPicture(page, 1200, 900, 'image/jpeg');
  await page.evaluate(() => {
    const blank = (canvas: OffscreenCanvas | HTMLCanvasElement) => {
      const g = canvas.getContext('2d') as CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D;
      g.save();
      g.setTransform(1, 0, 0, 1, 0, 0);
      g.fillStyle = 'white';
      g.fillRect(0, 0, canvas.width, canvas.height);
      g.restore();
    };
    const convert = OffscreenCanvas.prototype.convertToBlob;
    OffscreenCanvas.prototype.convertToBlob = function (this: OffscreenCanvas, o?: ImageEncodeOptions) {
      blank(this);
      return convert.call(this, o);
    };
    const toBlob = HTMLCanvasElement.prototype.toBlob;
    HTMLCanvasElement.prototype.toBlob = function (this: HTMLCanvasElement, cb: BlobCallback, t?: string, q?: number) {
      blank(this);
      return toBlob.call(this, cb, t, q);
    };
  });
  await page.locator('input[type=file]').first().setInputFiles({ name: 'a.jpg', mimeType: 'image/jpeg', buffer: photo });
  await expect(page.getByRole('status').filter({ hasText: BLOCKED })).toBeVisible();
  expect(signs).toEqual([]);
});

// The review's MAJOR: a control disabled while it holds the focus leaves it
// on <body> in Chromium; the person tabbing on starts from the top. The sign
// is held so the busy state lasts; the loss is checked first (the control).
test('the focus comes back to the control that was busy, on all four surfaces', async ({ page }) => {
  test.setTimeout(60_000);
  const release = await holdSigns(page);
  const releases: (() => void)[] = [release];
  const activeIs = (sel: string) => page.evaluate((s) => document.activeElement === document.querySelector(s), sel);
  const onBody = () => page.evaluate(() => document.activeElement === document.body);
  await openMedias(page);
  const photo = await plainPicture(page, 1200, 900, 'image/jpeg');

  // Médias → Photos: the input inside its label.
  const photosInput = page.locator('input[type=file]').first();
  await photosInput.focus();
  const shown = await page.locator('main img').count();
  await photosInput.setInputFiles({ name: 'a.jpg', mimeType: 'image/jpeg', buffer: photo });
  await expect(page.getByText('Téléversement…')).toBeVisible();
  await expect.poll(onBody, { message: 'Chromium kept the focus on the disabled input' }).toBe(true);
  releases.shift()!();
  await expect(page.locator('main img')).toHaveCount(shown + 1);
  await expect.poll(() => activeIs('main input[type=file]')).toBe(true);
  await page.unroute('**/api/pro/uploads/sign');

  // Médias → Avant / Après: « Avant ».
  releases.push(await holdSigns(page));
  await page.getByRole('button', { name: 'Avant / Après' }).click();
  const avant = page.locator('label', { hasText: /^Avant/ }).locator('input[type=file]');
  await avant.focus();
  await avant.setInputFiles({ name: 'b.jpg', mimeType: 'image/jpeg', buffer: photo });
  await expect(page.getByText('Téléversement…')).toBeVisible();
  await expect.poll(onBody).toBe(true);
  releases.shift()!();
  await expect(page.locator('label', { hasText: 'Avant ✓' })).toBeVisible();
  await expect.poll(() => page.evaluate(() => document.activeElement?.closest('label')?.textContent ?? '')).toBe('Avant ✓');
  await page.unroute('**/api/pro/uploads/sign');

  // Profil → « Ajouter un logo ».
  releases.push(await holdSigns(page));
  await page.goto('/pro/profil');
  await expect(page.getByLabel('Nom du salon')).toBeVisible();
  const logoButton = page.getByRole('button', { name: /(Ajouter un|Changer le) logo$/ });
  await logoButton.focus();
  await page.getByLabel('Logo du salon').setInputFiles({ name: 'l.jpg', mimeType: 'image/jpeg', buffer: photo });
  await expect(logoButton).toHaveAttribute('aria-busy', 'true');
  await expect.poll(onBody).toBe(true);
  releases.shift()!();
  const changeLogo = page.getByRole('button', { name: 'Changer le logo' });
  await expect(changeLogo).toBeVisible();
  await expect(changeLogo).toBeFocused();
  await page.unroute('**/api/pro/uploads/sign');

  // Catalogue → Employés → « Ajouter une photo ».
  releases.push(await holdSigns(page));
  await page.goto('/pro/catalogue');
  await page.getByRole('button', { name: 'Employés' }).click();
  await page.getByRole('button', { name: 'Ajouter un employé' }).click();
  const staffButton = page.getByRole('button', { name: /Ajouter une photo$/ });
  await staffButton.focus();
  await page.getByLabel('Photo de l’employé').setInputFiles({ name: 's.jpg', mimeType: 'image/jpeg', buffer: photo });
  await expect(staffButton).toHaveAttribute('aria-busy', 'true');
  await expect.poll(onBody).toBe(true);
  releases.shift()!();
  const changePhoto = page.getByRole('button', { name: 'Changer la photo' });
  await expect(changePhoto).toBeVisible();
  await expect(changePhoto).toBeFocused();
});

// §2.7: at 320 px the 85-character « trop grande » sentence wraps inside the
// toast pill and the pill stays whole on the screen. These three bounds hold
// for `main`'s toast; a23eda47 had removed them together with the one bound
// that only the full-width toast met (§13.8).
test('at 320 px the « trop grande » toast stays on the screen, with no sideways scroll', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 568 });
  await openMedias(page);
  await page.getByRole('button', { name: 'Avant / Après' }).click();
  await page
    .locator('label', { hasText: /^Avant/ })
    .locator('input[type=file]')
    .setInputFiles({ name: 'avant.jpg', mimeType: 'image/jpeg', buffer: headerOnlyJpeg(12000, 9000) });
  const pill = page.getByRole('status').filter({ hasText: TOO_LARGE }).locator('> div');
  await expect(pill).toBeVisible();
  const box = (await pill.boundingBox())!;
  const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
  const seen = `pill ${JSON.stringify(box)}, scrollWidth ${scrollWidth}`;
  expect(box.x, seen).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width, seen).toBeLessThanOrEqual(320);
  expect(scrollWidth, seen).toBeLessThanOrEqual(320);
  // The KNOWN RESIDUAL, pinned so it cannot change unseen (§2.7, §11 item 13):
  // the region is centred by `left-1/2 -translate-x-1/2` with no width, so the
  // pill has at most half the screen to wrap in — 160 px here, normal text.
  // It flips with the follow-up that widens the shared toast, which changes
  // this line, on the owner's word.
  expect(box.width, seen).toBeLessThanOrEqual(161);
});

import { type APIRequestContext, type Page, expect, test } from '@playwright/test';

import { signInPro } from './_auth';
import {
  exifApp1,
  headerOnlyJpeg,
  ijgLumaTable,
  inspectJpeg,
  type JpegInspection,
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

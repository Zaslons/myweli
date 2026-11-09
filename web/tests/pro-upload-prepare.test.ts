import { afterEach, describe, expect, it, vi } from 'vitest';

const captureMessage = vi.fn();
vi.mock('@sentry/nextjs', () => ({ captureMessage: (...a: unknown[]) => captureMessage(...a) }));

const {
  uploadGalleryImage,
  uploadKycDocument,
  uploadLogoImage,
  uploadFailureMessage,
  UPLOAD_TOO_LARGE_MESSAGE,
  UPLOAD_UNREADABLE_MESSAGE,
} = await import('../lib/pro/upload');
import type { PrepareResult } from '../lib/image/compress';

/// docs/design/web-pro-upload-resize.md §8.1 — `upload.ts` with an injected
/// `compress` (the app's `ImageCompressor` seam): what is signed, what is sent,
/// and what is said when the photo cannot be prepared.

const SIGNED = {
  method: 'PUT',
  uploadUrl: 'https://r2.example/pending/gallery/p1/abc.jpg?X-Amz-Signature=s',
  headers: { 'content-type': 'image/jpeg' },
  publicUrl: 'https://cdn.example/pending/gallery/p1/abc.jpg',
  maxBytes: 5_242_880,
};

function storage(signBody: Record<string, unknown> = SIGNED) {
  const fetchMock = vi.fn(async (url: string) => {
    if (url === '/api/pro/uploads/sign') return new Response(JSON.stringify(signBody), { status: 200 });
    return new Response(null, { status: 200 });
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

const prepared = (bytes = 3): PrepareResult => ({
  ok: true,
  blob: new Blob([new Uint8Array(bytes)], { type: 'image/jpeg' }),
  width: 1600,
  height: 2133,
  pixels: 12_192_768,
});

afterEach(() => {
  vi.unstubAllGlobals();
  captureMessage.mockClear();
});

describe('a Pro photo is prepared, then signed as JPEG, then the PREPARED bytes are sent', () => {
  for (const [name, upload, purpose] of [
    ['uploadGalleryImage', uploadGalleryImage, 'gallery'],
    ['uploadLogoImage', uploadLogoImage, 'logo'],
  ] as const) {
    it(`${name}: signs image/jpeg whatever was picked, PUTs the prepared blob, not the File`, async () => {
      const fetchMock = storage();
      const file = new File([new Uint8Array(9_000)], 'logo.png', { type: 'image/png' });
      const result = prepared();
      const compress = vi.fn(async () => result);

      expect(await upload(file, { compress })).toEqual({ ok: true, url: SIGNED.publicUrl });
      expect(compress).toHaveBeenCalledWith(file);
      expect(fetchMock).toHaveBeenCalledTimes(2);
      const [signUrl, signInit] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
      expect(signUrl).toBe('/api/pro/uploads/sign');
      expect(JSON.parse(String(signInit.body))).toEqual({ contentType: 'image/jpeg', purpose });
      const [putUrl, putInit] = fetchMock.mock.calls[1] as unknown as [string, RequestInit];
      expect(putUrl).toBe(SIGNED.uploadUrl);
      expect(putInit.method).toBe('PUT');
      expect(putInit.headers).toEqual({ 'content-type': 'image/jpeg' });
      expect(putInit.body).toBe((result as { blob: Blob }).blob);
      expect(putInit.body).not.toBe(file);
      expect(captureMessage).not.toHaveBeenCalled();
    });
  }
});

describe('a photo that cannot be prepared spends no signature and says why', () => {
  for (const reason of ['unreadable', 'too_large', 'failed'] as const) {
    it(`${reason}: no request at all, { ok: false, reason }, a « prepare » report`, async () => {
      const fetchMock = storage();
      const file = new File([new Uint8Array(10)], 'IMG_0042 chez Awa.heic', { type: 'image/heic' });
      const pixels = reason === 'too_large' ? 108_000_000 : null;
      const r = await uploadGalleryImage(file, { compress: async () => ({ ok: false, reason, pixels }) });

      expect(r).toEqual({ ok: false, reason });
      expect(fetchMock).not.toHaveBeenCalled();
      expect(captureMessage).toHaveBeenCalledTimes(1);
      const [msg, opts] = captureMessage.mock.calls[0] as [string, { tags: Record<string, string> }];
      expect(msg).toBe('upload_failed:gallery:prepare');
      expect(opts.tags).toMatchObject({
        upload_stage: 'prepare',
        upload_purpose: 'gallery',
        upload_prepare_reason: reason,
        upload_input_type: 'image/heic',
        upload_megapixels: reason === 'too_large' ? '>64' : 'unknown',
      });
      // Never the file name — it is user content (here, a client's name).
      const serialized = JSON.stringify(captureMessage.mock.calls);
      expect(serialized).not.toContain('IMG_0042');
      expect(serialized).not.toContain('Awa');
      expect(serialized).not.toContain('.heic');
    });
  }

  it('the logo reports under its own purpose', async () => {
    storage();
    const file = new File(['x'], 'logo.svg', { type: 'image/svg+xml' });
    await uploadLogoImage(file, { compress: async () => ({ ok: false, reason: 'unreadable', pixels: null }) });
    expect(captureMessage.mock.calls[0][0]).toBe('upload_failed:logo:prepare');
  });

  it('a type that is not MIME-shaped is reported as « unknown »', async () => {
    storage();
    const file = new File(['x'], 'a', { type: 'Photo de Mme Koné' });
    await uploadGalleryImage(file, { compress: async () => ({ ok: false, reason: 'unreadable', pixels: null }) });
    const [, opts] = captureMessage.mock.calls[0] as [string, { tags: Record<string, string> }];
    expect(opts.tags.upload_input_type).toBe('unknown');
    expect(JSON.stringify(captureMessage.mock.calls)).not.toContain('Koné');
  });
});

describe('the server’s maxBytes is the last guard before the PUT', () => {
  it('a prepared file over the signed maxBytes is not sent: too_large', async () => {
    const fetchMock = storage({ ...SIGNED, maxBytes: 100 });
    const file = new File(['x'], 'p.jpg', { type: 'image/jpeg' });
    const r = await uploadGalleryImage(file, { compress: async () => prepared(101) });
    expect(r).toEqual({ ok: false, reason: 'too_large' });
    expect(fetchMock).toHaveBeenCalledTimes(1); // the sign, no PUT
    expect(captureMessage.mock.calls[0][0]).toBe('upload_failed:gallery:prepare');
  });

  it('at the cap, or with no maxBytes in the answer, it is sent', async () => {
    for (const body of [{ ...SIGNED, maxBytes: 101 }, { ...SIGNED, maxBytes: undefined }]) {
      const fetchMock = storage(body);
      const r = await uploadGalleryImage(new File(['x'], 'p.jpg'), { compress: async () => prepared(101) });
      expect(r.ok).toBe(true);
      expect(fetchMock).toHaveBeenCalledTimes(2);
    }
  });
});

describe('the sentences', () => {
  it('are the spec’s, typographic apostrophes, « vous »', () => {
    expect(UPLOAD_UNREADABLE_MESSAGE).toBe(
      'Cette image n’a pas pu être lue. Choisissez une image JPEG, PNG ou WebP.',
    );
    expect(UPLOAD_TOO_LARGE_MESSAGE).toBe(
      'Cette image est trop grande pour être préparée ici. Choisissez une image plus petite.',
    );
    expect(UPLOAD_UNREADABLE_MESSAGE).not.toContain("'");
  });

  it('unreadable and too_large have theirs; failed keeps the surface’s', () => {
    expect(uploadFailureMessage('unreadable', 'Échec de l’envoi')).toBe(UPLOAD_UNREADABLE_MESSAGE);
    expect(uploadFailureMessage('too_large', 'Échec de l’envoi')).toBe(UPLOAD_TOO_LARGE_MESSAGE);
    expect(uploadFailureMessage('failed', 'Échec de l’envoi du logo.')).toBe('Échec de l’envoi du logo.');
  });
});

describe('KYC is not prepared (owner’s answer 2: Pro photos only)', () => {
  it('signs the picked type and PUTs the File itself, as before', async () => {
    const fetchMock = vi.fn(async (url: string) => {
      if (url === '/api/pro/uploads/sign') {
        return new Response(
          JSON.stringify({ method: 'PUT', uploadUrl: 'https://r2.example/k', headers: {}, key: 'kyc/acc1/1.pdf' }),
          { status: 200 },
        );
      }
      return new Response(null, { status: 200 });
    });
    vi.stubGlobal('fetch', fetchMock);
    const file = new File(['%PDF'], 'piece.pdf', { type: 'application/pdf' });
    expect(await uploadKycDocument(file)).toEqual({ key: 'kyc/acc1/1.pdf', fileName: 'piece.pdf' });
    const [, signInit] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(JSON.parse(String(signInit.body))).toEqual({ contentType: 'application/pdf', purpose: 'kyc' });
    const [, putInit] = fetchMock.mock.calls[1] as unknown as [string, RequestInit];
    expect(putInit.body).toBe(file);
  });
});

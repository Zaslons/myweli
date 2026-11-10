import { afterEach, describe, expect, it, vi } from 'vitest';

const captureMessage = vi.fn();
vi.mock('@sentry/nextjs', () => ({ captureMessage: (...a: unknown[]) => captureMessage(...a) }));

const { uploadGalleryImage, uploadKycDocument, uploadLogoImage } = await import(
  '../lib/pro/upload'
);

/// docs/design/web-pro-network-failure.md §5 — the presign request (to the
/// pro BFF, same origin) with no network. Before: it threw, and the photo
/// button of the gallery, the before/after, the employee card, the logo and
/// the KYC documents spun for ever. Now: a failed upload, the branch every
/// caller already has (« Échec de l’envoi de la photo. »…) — `{ ok: false,
/// reason: 'failed' }` for the Pro photos since they are prepared first
/// (web-pro-upload-resize.md; jsdom has no canvas, so `compress` is injected),
/// `null` for KYC.
///
/// Not reported: a same-origin request that never answers is the person's
/// network — not storage refusing us, nor a CORS rule, which is what the
/// upload telemetry exists to find.
const file = new File(['x'], 'photo.jpg', { type: 'image/jpeg' });
const compress = async () =>
  ({ ok: true, blob: new Blob(['j'], { type: 'image/jpeg' }), width: 1, height: 1, pixels: 1 }) as const;

afterEach(() => {
  vi.unstubAllGlobals();
  captureMessage.mockClear();
});

describe('a presign with no network is a failed upload, not a spinner for ever', () => {
  for (const [name, upload, failure] of [
    ['uploadGalleryImage', (f: File) => uploadGalleryImage(f, { compress }), { ok: false, reason: 'failed' }],
    ['uploadLogoImage', (f: File) => uploadLogoImage(f, { compress }), { ok: false, reason: 'failed' }],
    ['uploadKycDocument', uploadKycDocument, null],
  ] as const) {
    it(`${name}: a failure, nothing sent to storage, nothing reported`, async () => {
      const fetchMock = vi.fn().mockRejectedValue(new TypeError('Failed to fetch'));
      vi.stubGlobal('fetch', fetchMock);

      await expect(upload(file)).resolves.toEqual(failure);
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(fetchMock.mock.calls[0][0]).toBe('/api/pro/uploads/sign');
      expect(captureMessage).not.toHaveBeenCalled();
    });
  }
});

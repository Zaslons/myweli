import { afterEach, describe, expect, it, vi } from 'vitest';

const captureMessage = vi.fn();
vi.mock('@sentry/nextjs', () => ({ captureMessage: (...a: unknown[]) => captureMessage(...a) }));

const { uploadGalleryImage, uploadKycDocument, uploadLogoImage } = await import(
  '../lib/pro/upload'
);

/// docs/design/web-pro-network-failure.md §5 — the presign request (to the
/// pro BFF, same origin) with no network. Before: it threw, and the photo
/// button of the gallery, the before/after, the employee card, the logo and
/// the KYC documents spun for ever. Now: `null`, the branch every caller
/// already has (« Échec de l’envoi de la photo. »…).
///
/// Not reported: a same-origin request that never answers is the person's
/// network — not storage refusing us, nor a CORS rule, which is what the
/// upload telemetry exists to find.
const file = new File(['x'], 'photo.jpg', { type: 'image/jpeg' });

afterEach(() => {
  vi.unstubAllGlobals();
  captureMessage.mockClear();
});

describe('a presign with no network is a failed upload, not a spinner for ever', () => {
  for (const [name, upload] of [
    ['uploadGalleryImage', uploadGalleryImage],
    ['uploadLogoImage', uploadLogoImage],
    ['uploadKycDocument', uploadKycDocument],
  ] as const) {
    it(`${name}: null, nothing sent to storage, nothing reported`, async () => {
      const fetchMock = vi.fn().mockRejectedValue(new TypeError('Failed to fetch'));
      vi.stubGlobal('fetch', fetchMock);

      await expect(upload(file)).resolves.toBeNull();
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(fetchMock.mock.calls[0][0]).toBe('/api/pro/uploads/sign');
      expect(captureMessage).not.toHaveBeenCalled();
    });
  }
});

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  type BeforeAfterPair,
  canAddPair,
  canAddPhoto,
  moveItem,
  toCover,
  removeAt,
} from '../lib/pro/medias';
import { uploadGalleryImage } from '../lib/pro/upload';

describe('pro medias helpers', () => {
  it('moveItem swaps neighbours; no-op at edges', () => {
    expect(moveItem(['a', 'b', 'c'], 0, 1)).toEqual(['b', 'a', 'c']);
    expect(moveItem(['a', 'b', 'c'], 2, 1)).toEqual(['a', 'b', 'c']); // bottom
    expect(moveItem(['a', 'b', 'c'], 0, -1)).toEqual(['a', 'b', 'c']); // top
  });

  it('toCover promotes to the head, relative order preserved; no-op at 0/oob', () => {
    expect(toCover(['a', 'b', 'c', 'd'], 2)).toEqual(['c', 'a', 'b', 'd']);
    expect(toCover(['a', 'b', 'c'], 0)).toEqual(['a', 'b', 'c']); // already cover
    expect(toCover(['a', 'b', 'c'], 3)).toEqual(['a', 'b', 'c']); // oob
    expect(toCover(['a', 'b', 'c'], -1)).toEqual(['a', 'b', 'c']);
  });

  it('removeAt drops the index', () => {
    expect(removeAt(['a', 'b', 'c'], 1)).toEqual(['a', 'c']);
  });

  it('caps gallery (20) and pairs (12)', () => {
    expect(canAddPhoto(new Array(19).fill('x'))).toBe(true);
    expect(canAddPhoto(new Array(20).fill('x'))).toBe(false);
    const pairs = new Array(12).fill({ before: 'b', after: 'a' }) as BeforeAfterPair[];
    expect(canAddPair(pairs)).toBe(false);
  });
});

describe('uploadGalleryImage', () => {
  afterEach(() => vi.restoreAllMocks());
  // jsdom has no canvas: the preparation is injected (web-pro-upload-resize.md).
  const prepared = new Blob(['jpeg'], { type: 'image/jpeg' });
  const compress = async () => ({ ok: true, blob: prepared, width: 1, height: 1, pixels: 1 }) as const;

  it('signs → PUTs the prepared bytes → returns publicUrl', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            method: 'POST',
            uploadUrl: 'https://r2/upload',
            fields: { key: 'gallery/p1/1.jpg' },
            publicUrl: 'https://cdn/p1/1.jpg',
          }),
          { status: 200 },
        ),
      )
      .mockResolvedValueOnce(new Response(null, { status: 204 }));
    vi.stubGlobal('fetch', fetchMock);

    const file = new File(['x'], 'p.jpg', { type: 'image/jpeg' });
    const upload = await uploadGalleryImage(file, { compress });
    expect(upload).toEqual({ ok: true, url: 'https://cdn/p1/1.jpg' });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(String(fetchMock.mock.calls[0][0])).toContain('/api/pro/uploads/sign');
    expect(String(fetchMock.mock.calls[1][0])).toBe('https://r2/upload');
    expect(fetchMock.mock.calls[1][1]?.body).toBe(prepared);
  });

  it('fails when the storage PUT fails', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({ uploadUrl: 'https://r2/u', publicUrl: 'https://cdn/x' }),
          { status: 200 },
        ),
      )
      .mockResolvedValueOnce(new Response(null, { status: 500 }));
    vi.stubGlobal('fetch', fetchMock);
    const file = new File(['x'], 'p.jpg', { type: 'image/jpeg' });
    expect(await uploadGalleryImage(file, { compress })).toEqual({ ok: false, reason: 'failed' });
  });
});

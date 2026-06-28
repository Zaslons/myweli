import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  type BeforeAfterPair,
  canAddPair,
  canAddPhoto,
  moveItem,
  removeAt,
} from '../lib/pro/medias';
import { uploadGalleryImage } from '../lib/pro/upload';

describe('pro medias helpers', () => {
  it('moveItem swaps neighbours; no-op at edges', () => {
    expect(moveItem(['a', 'b', 'c'], 0, 1)).toEqual(['b', 'a', 'c']);
    expect(moveItem(['a', 'b', 'c'], 2, 1)).toEqual(['a', 'b', 'c']); // bottom
    expect(moveItem(['a', 'b', 'c'], 0, -1)).toEqual(['a', 'b', 'c']); // top
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

  it('signs → POSTs bytes → returns publicUrl', async () => {
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
    const url = await uploadGalleryImage(file);
    expect(url).toBe('https://cdn/p1/1.jpg');
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(String(fetchMock.mock.calls[0][0])).toContain('/api/pro/uploads/sign');
    expect(String(fetchMock.mock.calls[1][0])).toBe('https://r2/upload');
  });

  it('returns null when the storage POST fails', async () => {
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
    expect(await uploadGalleryImage(file)).toBeNull();
  });
});

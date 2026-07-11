import { describe, expect, it } from 'vitest';
import {
  MAX_REVIEW_PHOTOS,
  addPhoto,
  canAddPhoto,
  removePhoto,
} from '../lib/account/review-photos';

describe('review photo list (parity 2.13 — the app\u2019s \u22643 rule)', () => {
  it('caps at MAX_REVIEW_PHOTOS', () => {
    let urls: string[] = [];
    for (let i = 0; i < 5; i++) urls = addPhoto(urls, `u${i}`);
    expect(urls).toHaveLength(MAX_REVIEW_PHOTOS);
    expect(canAddPhoto(urls)).toBe(false);
  });

  it('removes by index', () => {
    expect(removePhoto(['a', 'b', 'c'], 1)).toEqual(['a', 'c']);
    expect(canAddPhoto(['a'])).toBe(true);
  });
});

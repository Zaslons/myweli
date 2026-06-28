import { describe, expect, it } from 'vitest';
import {
  canRebook,
  canReview,
  isValidRating,
  toggleId,
} from '../lib/account/extras';

describe('account extras', () => {
  it('isValidRating: integers 1..5', () => {
    expect(isValidRating(1)).toBe(true);
    expect(isValidRating(5)).toBe(true);
    expect(isValidRating(0)).toBe(false);
    expect(isValidRating(6)).toBe(false);
    expect(isValidRating(3.5)).toBe(false);
  });

  it('toggleId adds/removes', () => {
    expect(toggleId(['a'], 'b')).toEqual(['a', 'b']);
    expect(toggleId(['a', 'b'], 'a')).toEqual(['b']);
  });

  it('canRebook on terminal states; canReview only completed', () => {
    expect(canRebook('completed')).toBe(true);
    expect(canRebook('cancelled')).toBe(true);
    expect(canRebook('noShow')).toBe(true);
    expect(canRebook('confirmed')).toBe(false);
    expect(canReview('completed')).toBe(true);
    expect(canReview('cancelled')).toBe(false);
  });
});

import { describe, expect, it } from 'vitest';
import type { Appointment } from '../lib/account/appointments';
import {
  canRebook,
  canReview,
  isValidRating,
  toggleId,
} from '../lib/account/extras';

const NOW = new Date('2026-11-23T12:00:00.000Z');
const at = (minutes: number) => new Date(NOW.getTime() + minutes * 60_000).toISOString();
const live = (status: string, minutes: number): Appointment => ({
  id: 'a',
  status,
  appointmentDate: at(minutes),
  providerId: 'p1',
  providerSlug: 'beaute-divine',
});

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

  it('canReview only completed', () => {
    expect(canReview('completed')).toBe(true);
    expect(canReview('cancelled')).toBe(false);
  });

  // Decision 183: any booking that is not upcoming, at a salon still open.
  it('canRebook: every booking that is not upcoming, across the table', () => {
    const rows: [string, number, boolean][] = [
      ['pending', 60, false],
      ['confirmed', 60, false],
      ['pending', -60, true], // « Non confirmé » — gained in A1w
      ['confirmed', -60, true], // a past « Confirmé » — gained in A1w
      ['pending', 0, true], // exactly now is past
      ['completed', -60, true],
      ['completed', 60, true],
      ['noShow', -60, true],
      ['NO_SHOW', -60, true],
      ['cancelled', -60, true],
      ['cancelled', 60, true],
    ];
    for (const [status, minutes, want] of rows) {
      expect(canRebook(live(status, minutes), NOW), `${status} ${minutes}`).toBe(want);
    }
  });

  it('canRebook: never at a salon that stopped, one this build does not know, or with no slug', () => {
    const past = live('completed', -60);
    expect(canRebook({ ...past, providerStatus: 'suspended' }, NOW)).toBe(false);
    expect(canRebook({ ...past, providerStatus: 'draft' }, NOW)).toBe(false);
    expect(
      canRebook({ ...past, providerStatus: 'archived' as Appointment['providerStatus'] }, NOW),
    ).toBe(false);
    expect(canRebook({ ...past, providerSlug: undefined }, NOW)).toBe(false);
    // The pair: an absent status means live, or « always false » would pass.
    expect(canRebook({ ...past, providerStatus: null }, NOW)).toBe(true);
    expect(canRebook({ ...past, providerStatus: 'active' }, NOW)).toBe(true);
  });
});

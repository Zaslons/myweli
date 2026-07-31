import { describe, expect, it } from 'vitest';
import {
  emptyReason,
  firstBookableDay,
  formatNotice,
  lastBookableDay,
  shiftSalonDay,
} from '../lib/booking/window';
import { salonToday } from '../lib/time';

/// A14d — web's classification of an empty day, mirroring mobile's
/// `SlotPicker._emptyReason`. The two must agree, or the same salon explains
/// itself differently depending on which surface the client opened.
describe('the bookable window — why is this day empty?', () => {
  const tz = 'Africa/Abidjan';
  const today = salonToday(new Date(), tz);

  it('a day past the horizon is named as such', () => {
    expect(
      emptyReason({
        date: shiftSalonDay(today, 40, tz),
        horizonDays: 30,
        noticeMinutes: 60,
        tz,
      }),
    ).toBe('beyondHorizon');
  });

  it('the last bookable day is INCLUSIVE', () => {
    // The server refuses only days strictly AFTER today + horizon, so an
    // off-by-one here hides a day the API would accept.
    expect(
      emptyReason({
        date: shiftSalonDay(today, 30, tz),
        horizonDays: 30,
        noticeMinutes: 60,
        tz,
      }),
    ).toBe('full');
    expect(
      emptyReason({
        date: shiftSalonDay(today, 31, tz),
        horizonDays: 30,
        noticeMinutes: 60,
        tz,
      }),
    ).toBe('beyondHorizon');
  });

  it('a notice longer than a day reaches into future days', () => {
    // The structural point A14d fixed on both platforms: a 48-hour notice must
    // exclude TOMORROW, not merely part of today.
    expect(
      emptyReason({
        date: shiftSalonDay(today, 1, tz),
        horizonDays: 365,
        noticeMinutes: 48 * 60,
        tz,
      }),
    ).toBe('tooSoon');
    expect(
      emptyReason({
        date: shiftSalonDay(today, 4, tz),
        horizonDays: 365,
        noticeMinutes: 48 * 60,
        tz,
      }),
    ).toBe('full');
  });

  it('a past day says it has passed, not that it is too soon', () => {
    expect(
      emptyReason({
        date: shiftSalonDay(today, -30, tz),
        horizonDays: 365,
        noticeMinutes: 60,
        tz,
      }),
    ).toBe('past');
  });

  it('an ordinary day inside the window is simply full', () => {
    // The control. Without it every assertion above passes for a classifier
    // that never returns `full`.
    expect(
      emptyReason({
        date: shiftSalonDay(today, 5, tz),
        horizonDays: 365,
        noticeMinutes: 60,
        tz,
      }),
    ).toBe('full');
  });

  it('the jump targets are the edges themselves', () => {
    expect(lastBookableDay(30, tz)).toBe(shiftSalonDay(today, 30, tz));
    expect(firstBookableDay(0, tz)).toBe(today);
  });

  it('shifting days crosses a month boundary correctly', () => {
    expect(shiftSalonDay('2026-01-31', 1, tz)).toBe('2026-02-01');
    expect(shiftSalonDay('2026-03-01', -1, tz)).toBe('2026-02-28');
    expect(shiftSalonDay('2024-02-28', 1, tz)).toBe('2024-02-29'); // leap
  });

  it('the delay reads the way a pro set it', () => {
    expect(formatNotice(30)).toBe('30 min');
    expect(formatNotice(60)).toBe('1 h');
    expect(formatNotice(2880)).toBe('48 h');
    expect(formatNotice(90)).toBe('1 h 30');
  });
});

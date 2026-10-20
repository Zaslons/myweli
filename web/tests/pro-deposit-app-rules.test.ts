import { describe, expect, it } from 'vitest';

import {
  DEPOSIT_PERCENT_RANGE,
  DEPOSIT_SAMPLE_TOTAL,
  WINDOW_CHOICES,
  depositExample,
  sliderPosition,
  windowChoices,
} from '../lib/pro/deposit';

/// docs/design/web-pro-deposit-app-rules.md — the app's deposit rules
/// (`deposit_settings_screen.dart`) on the web: a 5–80 % slider by steps of
/// 5, 12 / 24 / 48 h, the example on a 20 000 service.

describe('the app’s choices', () => {
  it('5–80 % by 5, and 12 / 24 / 48 h', () => {
    expect(DEPOSIT_PERCENT_RANGE).toEqual({ min: 5, max: 80, step: 5 });
    expect(WINDOW_CHOICES).toEqual([12, 24, 48]);
    expect(DEPOSIT_SAMPLE_TOTAL).toBe(20000);
  });
});

describe('depositExample — the app’s computeDeposit (round(total × %))', () => {
  it('30 % of 20 000', () => {
    expect(depositExample(30)).toEqual({ deposit: 6000, balance: 14000 });
  });
  it('a value from before the slider is computed as it is', () => {
    expect(depositExample(37.5)).toEqual({ deposit: 7500, balance: 12500 });
  });
  it('rounds to the franc', () => {
    expect(depositExample(33.33, 1000)).toEqual({ deposit: 333, balance: 667 });
  });
});

describe('sliderPosition — the thumb never leaves the track', () => {
  it('a value on the track stays', () => {
    expect(sliderPosition('45')).toBe(45);
  });
  it('a value from before sits at its end until moved', () => {
    expect(sliderPosition('100')).toBe(80);
    expect(sliderPosition('1')).toBe(5);
  });
  it('an unreadable one sits at the proposal', () => {
    expect(sliderPosition('')).toBe(30);
  });
});

describe('windowChoices — a saved delay outside the three is shown, not lost', () => {
  it('one of the three: the three', () => {
    expect(windowChoices(24)).toEqual([12, 24, 48]);
  });
  it('72 h from before: a fourth choice, in order', () => {
    expect(windowChoices(72)).toEqual([12, 24, 48, 72]);
    expect(windowChoices(6)).toEqual([6, 12, 24, 48]);
  });
});

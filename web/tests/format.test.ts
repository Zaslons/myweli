import { describe, expect, it } from 'vitest';
import {
  formatDateFr,
  formatDateTimeFr,
  formatDuration,
  formatFcfa,
  priceRange,
} from '../lib/format';

const norm = (s: string) => s.replace(/\s/g, ' ');

describe('format', () => {
  it('formats FCFA with grouping', () => {
    expect(norm(formatFcfa(15000))).toBe('15 000 FCFA');
  });

  it('XOF and XAF both read FCFA; other ISO codes render as themselves', () => {
    expect(norm(formatFcfa(15000, 'XOF'))).toBe('15 000 FCFA');
    expect(norm(formatFcfa(15000, 'XAF'))).toBe('15 000 FCFA');
    expect(norm(formatFcfa(15000, 'GHS'))).toBe('15 000 GHS');
  });

  it('renders a price range only when a higher max is set', () => {
    expect(norm(priceRange(15000, 25000))).toBe('15 000 – 25 000 FCFA');
    expect(norm(priceRange(15000))).toBe('15 000 FCFA');
    expect(norm(priceRange(15000, 15000))).toBe('15 000 FCFA');
  });

  it('formats durations', () => {
    expect(formatDuration(90)).toBe('1 h 30');
    expect(formatDuration(60)).toBe('1 h');
    expect(formatDuration(45)).toBe('45 min');
  });

  it('dates render the SALON day, whatever the process/device TZ', () => {
    // 23:30Z stays the salon's July 13 — the old device-tz formatter rolled
    // it into the 14th on any zone east of Abidjan (the display-class leak).
    expect(formatDateFr('2026-07-13T23:30:00.000Z')).toBe('13 juillet 2026');
    expect(norm(formatDateTimeFr('2026-07-13T23:30:00.000Z'))).toBe(
      '13 juillet 2026 à 23:30',
    );
  });
});

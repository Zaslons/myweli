import { describe, expect, it } from 'vitest';
import { formatDuration, formatFcfa, priceRange } from '../lib/format';

const norm = (s: string) => s.replace(/\s/g, ' ');

describe('format', () => {
  it('formats FCFA with grouping', () => {
    expect(norm(formatFcfa(15000))).toBe('15 000 FCFA');
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
});

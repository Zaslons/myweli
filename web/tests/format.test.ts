import { describe, expect, it } from 'vitest';
import {
  formatDateFr,
  formatDateTimeFr,
  formatDuration,
  formatFcfa,
  formatPhoneNumber,
  priceRange,
} from '../lib/format';

const norm = (s: string) => s.replace(/\s/g, ' ');

/// The web twin of the app's `Formatters.formatPhoneNumber`
/// (docs/design/amounts-that-fit.md §5 « Web »).
///
/// **Compared exactly — `norm` is NOT used here, on purpose.** `norm` turns
/// every whitespace character into a plain space, which is right for `Intl`
/// output and would make these tests blind to the one thing they must pin: the
/// groups are separated by U+0020, so a copied number pastes with ordinary
/// spaces. Keeping the number on one line is the layout's job
/// (`whitespace-nowrap` on the card), never a no-break space in the string.
///
/// The first four vectors are the app's own, verbatim
/// (`mobile/test/unit/formatters_test.dart` — « Formatters.formatPhoneNumber »).
/// Nothing ties the two files together but these shared lines: a change to the
/// rule on one side must be made on the other.
describe('formatPhoneNumber — the twin of the app’s formatter', () => {
  it('groups a current 10-digit Côte d’Ivoire number in pairs', () => {
    expect(formatPhoneNumber('+2250712345678')).toBe('+225 07 12 34 56 78');
  });

  it('still groups a legacy 8-digit Côte d’Ivoire number', () => {
    expect(formatPhoneNumber('+22507123456')).toBe('+225 07 12 34 56');
  });

  it('returns a number without +225 unchanged', () => {
    expect(formatPhoneNumber('0601020304')).toBe('0601020304');
  });

  it('returns a wrong-length +225 number unchanged', () => {
    expect(formatPhoneNumber('+225071234')).toBe('+225071234'); // 6
    expect(formatPhoneNumber('+225070000010')).toBe('+225070000010'); // 9
    expect(formatPhoneNumber('+22507000001011')).toBe('+22507000001011'); // 11
  });

  it('the spec’s example and the e2e stub’s client', () => {
    expect(formatPhoneNumber('+2250700000101')).toBe('+225 07 00 00 01 01');
    expect(formatPhoneNumber('+2250700000001')).toBe('+225 07 00 00 00 01');
  });

  it('leaves a Gabon number as stored — a live market, not grouped', () => {
    expect(formatPhoneNumber('+24177000000')).toBe('+24177000000');
  });

  it('leaves a French number as stored', () => {
    expect(formatPhoneNumber('+33612345678')).toBe('+33612345678');
  });

  it('the separators are plain spaces (U+0020), five of them', () => {
    const out = formatPhoneNumber('+2250700000101');
    const gaps = Array.from(out).filter((c) => !/[\d+]/.test(c));
    expect(gaps.map((c) => c.codePointAt(0))).toEqual([
      0x20, 0x20, 0x20, 0x20, 0x20,
    ]);
  });

  it('a +225 number that already carries separators is re-grouped', () => {
    // Cleaned first, then tested — the app's order.
    expect(formatPhoneNumber('+225 07 00 00 01 01')).toBe('+225 07 00 00 01 01');
    expect(formatPhoneNumber('+225-0700-000-101')).toBe('+225 07 00 00 01 01');
  });

  it('the fall-through returns the ORIGINAL string, not the cleaned one', () => {
    expect(formatPhoneNumber('+33 6 12 34 56 78')).toBe('+33 6 12 34 56 78');
    expect(formatPhoneNumber('06 01 02 03 04')).toBe('06 01 02 03 04');
    expect(formatPhoneNumber('')).toBe('');
  });
});

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

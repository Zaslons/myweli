import { describe, expect, it } from 'vitest';
import { normalizePhone, phoneFieldError } from '../lib/phone';

/// The one phone rule, web side (docs/design/phone-national-length.md §2.1):
/// separators are stripped; empty — or a calling code alone — is EMPTY; a +225
/// number has exactly 10 digits after the calling code; any other country
/// keeps libphonenumber's verdict. The same vectors as the app's
/// `validators_test` and the backend's.
const TEN = 'Le numéro doit comporter 10 chiffres après +225.';
const REQUIRED = 'Saisissez un numéro de téléphone.';
const INVALID = 'Saisissez un numéro de téléphone valide.';

describe('phoneFieldError — a +225 number has exactly 10 digits', () => {
  it.each([
    ['+2250700000', '7 digits: the number the app accepted on 2026-10-15'],
    ['+225070000000011', '11 digits'],
    ['+2250700', '4 digits'],
    ['+225 07 07 12 34 5', '9 digits, spaced'],
  ])('%s (%s) says how many digits are needed', (value) => {
    expect(phoneFieldError(value, { required: true })).toBe(TEN);
    // Optional does not mean « anything goes »: a typed number is checked.
    expect(phoneFieldError(value, { required: false })).toBe(TEN);
  });

  it('separators are not digits: a spaced 10-digit number passes, and is sent bare', () => {
    expect(phoneFieldError('+225 07 07 12 34 56', { required: true })).toBeNull();
    expect(normalizePhone('+225 07 07 12 34 56')).toBe('+2250707123456');
    // Dashes, dots, brackets and the NBSP French formatting uses.
    expect(normalizePhone('+225-07.07(12)34 56')).toBe('+2250707123456');
    expect(phoneFieldError('+225-07.07(12)34 56', { required: true })).toBeNull();
  });
});

describe('phoneFieldError — empty, or a calling code alone, is EMPTY', () => {
  it.each([[''], ['+225'], [' + 225 '], ['+33'], [undefined]])(
    '%j: required asks for a number, optional accepts it and sends \'\'',
    (value) => {
      expect(phoneFieldError(value, { required: true })).toBe(REQUIRED);
      expect(phoneFieldError(value, { required: false })).toBeNull();
      expect(normalizePhone(value)).toBe('');
    },
  );
});

describe('phoneFieldError — another country keeps the generic rule', () => {
  it('a possible French number passes and normalizes', () => {
    expect(phoneFieldError('+33612345678', { required: true })).toBeNull();
    expect(normalizePhone('+33 6 12 34 56 78')).toBe('+33612345678');
  });

  it('an impossible one gets the generic sentence — never a length the API does not enforce', () => {
    // One digit short of France's 9: libphonenumber refuses it, and the
    // message stays generic (no « 9 chiffres après +33 »: +33 has no row in
    // the backend table).
    expect(phoneFieldError('+3361234567', { required: true })).toBe(INVALID);
  });

  it('a national form without the + is not E.164', () => {
    expect(phoneFieldError('0707123456', { required: true })).toBe(INVALID);
    expect(phoneFieldError('abc', { required: false })).toBe(INVALID);
  });
});

import { describe, expect, it } from 'vitest';
import {
  addressMentionsCommune,
  addressWithCommune,
  streetAddressWithoutCommune,
} from '../lib/address';

/// The address ↔ commune dedupe (fix/address-commune-dedupe). The owner's
/// page read « marcory, Rue des Nguéssous 93, Marcory » — typed data plus an
/// unconditional `, {commune}` append at three render sites.
describe('addressMentionsCommune — segments, never substrings', () => {
  it('matches a segment case- and accent-insensitively', () => {
    expect(addressMentionsCommune('marcory, Rue des Nguéssous 93', 'Marcory')).toBe(true);
    expect(addressMentionsCommune('Rue X, ATTECOUBE', 'Attécoubé')).toBe(true);
    expect(addressMentionsCommune('Rue X, attécoubé', 'Attecoube')).toBe(true);
  });

  it('a street NAMED after the commune is not a mention', () => {
    // « Rue de Marcory » in Marcory still deserves the append — only an
    // address whose own comma-segment IS the commune already says it.
    expect(addressMentionsCommune('Rue de Marcory 12', 'Marcory')).toBe(false);
  });

  it('empty inputs never match', () => {
    expect(addressMentionsCommune('', 'Marcory')).toBe(false);
    expect(addressMentionsCommune('Rue X', '')).toBe(false);
    expect(addressMentionsCommune(undefined, 'Marcory')).toBe(false);
  });
});

describe('addressWithCommune — the display line', () => {
  it('appends when the address does not say the commune', () => {
    expect(addressWithCommune('Rue des Jardins', 'Cocody')).toBe('Rue des Jardins, Cocody');
  });

  it('does NOT append when it already does — the screenshot case', () => {
    expect(addressWithCommune('marcory, Rue des Nguéssous 93', 'Marcory')).toBe(
      'marcory, Rue des Nguéssous 93',
    );
  });

  it('degrades to whichever half exists', () => {
    expect(addressWithCommune('', 'Cocody')).toBe('Cocody');
    expect(addressWithCommune('Rue X', null)).toBe('Rue X');
  });
});

describe('streetAddressWithoutCommune — the PostalAddress street line', () => {
  it('strips a leading or trailing commune segment', () => {
    expect(streetAddressWithoutCommune('marcory, Rue des Nguéssous 93', 'Marcory')).toBe(
      'Rue des Nguéssous 93',
    );
    expect(streetAddressWithoutCommune('Rue des Nguéssous 93, Marcory', 'Marcory')).toBe(
      'Rue des Nguéssous 93',
    );
  });

  it('leaves interior segments alone — over-stripping loses data', () => {
    expect(
      streetAddressWithoutCommune('Immeuble A, Marcory, Rue X', 'Marcory'),
    ).toBe('Immeuble A, Marcory, Rue X');
  });

  it('never strips down to nothing', () => {
    expect(streetAddressWithoutCommune('Marcory', 'Marcory')).toBe('Marcory');
  });

  it('absent address → undefined (the key drops out of the JSON-LD)', () => {
    expect(streetAddressWithoutCommune(undefined, 'Marcory')).toBeUndefined();
    expect(streetAddressWithoutCommune('', 'Marcory')).toBeUndefined();
  });
});

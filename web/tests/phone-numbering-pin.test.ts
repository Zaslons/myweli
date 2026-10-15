import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  type CountryCode,
  Metadata,
  getCountryCallingCode,
} from 'libphonenumber-js/min';
import metadata from 'libphonenumber-js/min/metadata';
import { describe, expect, it } from 'vitest';
import { PHONE_MARKETS, phoneFieldError } from '../lib/phone';

/// One fact, three surfaces (docs/design/phone-national-length.md §2.2/§8):
/// the backend table `nationalNumberLengths` is the authority, the app keeps
/// its own copy, and the web reads the length from libphonenumber's metadata
/// (the `min` build react-phone-number-input already ships). This reads the
/// backend source and holds the web to it: a metadata bump that changes a
/// market's length, or a new backend row the web does not enforce, goes red
/// here instead of in a salon's form.
const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const DART = readFileSync(
  join(REPO_ROOT, 'backend/lib/src/localities/phone_numbering.dart'),
  'utf-8',
);

/// `const Map<String, int> nationalNumberLengths = {'225': 10};`
/// → [['225', 10]].
function backendTable(): [string, number][] {
  const literal = /nationalNumberLengths\s*=\s*\{([^}]*)\}/.exec(DART);
  if (!literal) return [];
  return [...literal[1].matchAll(/'(\d+)'\s*:\s*(\d+)/g)].map((m) => [
    m[1],
    Number(m[2]),
  ]);
}

const TABLE = backendTable();

describe('national number lengths — backend table = libphonenumber metadata', () => {
  it('the backend table parses (a reformat must not empty this guard)', () => {
    expect(TABLE.length).toBeGreaterThan(0);
  });

  it.each(TABLE)(
    "+%s: its main country's possible lengths are exactly [%i]",
    (code, length) => {
      const main = metadata.country_calling_codes[code]?.[0] as
        | CountryCode
        | undefined;
      expect(main, `libphonenumber knows no country for +${code}`).toBeDefined();
      const plan = new Metadata();
      plan.selectNumberingPlan(main!);
      expect(plan.numberingPlan?.possibleLengths()).toEqual([length]);
    },
  );

  it('lib/phone enforces exactly the calling codes the backend does', () => {
    expect(PHONE_MARKETS.map((c) => getCountryCallingCode(c)).sort()).toEqual(
      TABLE.map(([code]) => code).sort(),
    );
  });

  it.each(TABLE)('+%s: the field asks for %i digits, and accepts them', (code, length) => {
    const message = `Le numéro doit comporter ${length} chiffres après +${code}.`;
    expect(
      phoneFieldError(`+${code}${'0'.repeat(length - 1)}`, { required: true }),
    ).toBe(message);
    expect(
      phoneFieldError(`+${code}${'0'.repeat(length + 1)}`, { required: true }),
    ).toBe(message);
    expect(
      phoneFieldError(`+${code}${'0'.repeat(length)}`, { required: true }),
    ).toBeNull();
  });
});

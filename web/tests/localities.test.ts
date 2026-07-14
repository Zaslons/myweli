import { describe, expect, it } from 'vitest';
import {
  allAreas,
  countryName,
  defaultCity,
  defaultCountry,
  emptyTree,
  findArea,
  findCity,
  operatorsFor,
  type LocalityTree,
} from '../lib/api/localities';

/// Multi-pays MP3 — the locality tree lookups (pure). The fixture mirrors
/// the backend seed (CI) + the Gabon market the e2e stub plays.
export const fixtureTree: LocalityTree = {
  countries: [
    {
      code: 'CI',
      name: "Côte d'Ivoire",
      currency: 'XOF',
      phonePrefix: '+225',
      operators: [
        { id: 'wave', label: 'Wave', deepLinkKind: 'wave' },
        { id: 'orangeMoney', label: 'Orange Money', deepLinkKind: null },
        { id: 'mtnMoMo', label: 'MTN MoMo', deepLinkKind: null },
        { id: 'moov', label: 'Moov Money', deepLinkKind: null },
      ],
      cities: [
        {
          id: 'abidjan',
          slug: 'abidjan',
          name: 'Abidjan',
          timezone: 'Africa/Abidjan',
          lat: 5.336,
          lng: -4.026,
          areas: [
            { id: 'cocody', slug: 'cocody', name: 'Cocody', labelKind: 'commune', lat: 5.36, lng: -4.0083 },
            { id: 'marcory', slug: 'marcory', name: 'Marcory', labelKind: 'commune', lat: 5.28, lng: -4.05 },
            { id: 'plateau', slug: 'plateau', name: 'Plateau', labelKind: 'commune', lat: 5.32, lng: -4.03 },
            { id: 'yopougon', slug: 'yopougon', name: 'Yopougon', labelKind: 'commune', lat: 5.32, lng: -4.08 },
            { id: 'treichville', slug: 'treichville', name: 'Treichville', labelKind: 'commune', lat: 5.293, lng: -4.01 },
            { id: 'adjame', slug: 'adjame', name: 'Adjamé', labelKind: 'commune', lat: 5.366, lng: -4.025 },
            { id: 'abobo', slug: 'abobo', name: 'Abobo', labelKind: 'commune', lat: 5.42, lng: -4.02 },
            { id: 'koumassi', slug: 'koumassi', name: 'Koumassi', labelKind: 'commune', lat: 5.29, lng: -3.945 },
            { id: 'port-bouet', slug: 'port-bouet', name: 'Port-Bouët', labelKind: 'commune', lat: 5.255, lng: -3.926 },
            { id: 'attecoube', slug: 'attecoube', name: 'Attécoubé', labelKind: 'commune', lat: 5.34, lng: -4.035 },
            { id: 'bingerville', slug: 'bingerville', name: 'Bingerville', labelKind: 'commune', lat: 5.355, lng: -3.89 },
          ],
        },
      ],
    },
    {
      code: 'GA',
      name: 'Gabon',
      currency: 'XAF',
      phonePrefix: '+241',
      operators: [
        { id: 'airtelMoney', label: 'Airtel Money', deepLinkKind: null },
      ],
      cities: [
        {
          id: 'libreville',
          slug: 'libreville',
          name: 'Libreville',
          timezone: 'Africa/Libreville',
          lat: 0.4162,
          lng: 9.4673,
          areas: [
            { id: 'glass', slug: 'glass', name: 'Glass', labelKind: 'quartier', lat: 0.3901, lng: 9.4544 },
          ],
        },
      ],
    },
  ],
};

describe('locality lookups', () => {
  it('defaultCountry/defaultCity = the first seeded market', () => {
    expect(defaultCountry(fixtureTree)?.code).toBe('CI');
    expect(defaultCity(fixtureTree)?.slug).toBe('abidjan');
    expect(defaultCountry(emptyTree)).toBeNull();
    expect(defaultCity(emptyTree)).toBeNull();
  });

  it('findCity/findArea resolve slugs across countries', () => {
    expect(findCity(fixtureTree, 'abidjan')?.name).toBe('Abidjan');
    expect(findCity(fixtureTree, 'libreville')?.timezone).toBe(
      'Africa/Libreville',
    );
    expect(findCity(fixtureTree, 'nulle-part')).toBeNull();
    const abidjan = findCity(fixtureTree, 'abidjan')!;
    expect(findArea(abidjan, 'port-bouet')?.name).toBe('Port-Bouët');
    expect(findArea(abidjan, 'glass')).toBeNull();
  });

  it('allAreas flattens every (city, area) pair, tree order', () => {
    const pairs = allAreas(fixtureTree);
    expect(pairs).toHaveLength(12);
    expect(pairs[0]!.area.slug).toBe('cocody');
    expect(pairs.at(-1)!.city.slug).toBe('libreville');
    expect(allAreas(emptyTree)).toEqual([]);
  });

  it('countryName resolves display names; null on a miss', () => {
    expect(countryName(fixtureTree, 'GA')).toBe('Gabon');
    expect(countryName(fixtureTree, 'CI')).toBe("Côte d'Ivoire");
    expect(countryName(fixtureTree, 'SN')).toBeNull();
    expect(countryName(fixtureTree, null)).toBeNull();
  });

  it("operatorsFor = the salon country's catalog; unknown → default country", () => {
    expect(operatorsFor(fixtureTree, 'GA').map((o) => o.id)).toEqual([
      'airtelMoney',
    ]);
    expect(operatorsFor(fixtureTree, 'CI')).toHaveLength(4);
    // Unknown/missing code falls back to the home market, never to nothing.
    expect(operatorsFor(fixtureTree, 'SN')).toHaveLength(4);
    expect(operatorsFor(fixtureTree, undefined)).toHaveLength(4);
    expect(operatorsFor(emptyTree, 'CI')).toEqual([]);
  });

  it('the Wave deep link rides deepLinkKind only (T56 — closed vocabulary)', () => {
    const ci = operatorsFor(fixtureTree, 'CI');
    expect(ci.find((o) => o.deepLinkKind === 'wave')?.id).toBe('wave');
    expect(ci.filter((o) => o.deepLinkKind === 'wave')).toHaveLength(1);
  });
});

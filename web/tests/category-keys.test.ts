import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { categoryList, categorySlugForApiKey } from '../lib/landing';
import { PROFILE_CATEGORIES } from '../lib/pro/profile';
import { categoryLabelFr, localBusinessJsonLd } from '../lib/seo/jsonld';
import { providerFixture } from './fixtures';

/// Every category key the website sends or compares is one the API stores
/// (docs/design/provider-category-column.md §12).
///
/// **What was here.** From M4 (#127) to 2026-11-24, « Onglerie » asked the
/// API for `category=nail`. Every writer stores `nails`: the PATCH enum, the
/// catalog's validation, the seed, `categoryFor`, the app, and this site's own
/// Pro profile. Both stores filter on exact equality. So the « Onglerie »
/// landing lists, the `/recherche` chip and the home page's link could never
/// show a salon. It type-checked because `GET /providers`' `category` is a
/// plain string in the contract.
///
/// **The oracle is the contract, read here, not a list copied into this
/// file.** A copied list is the very thing that drifted. The generated
/// `schema.ts` carries the same enum as a type (`ProviderCategory`, which
/// `Category.apiKey` and `PROFILE_CATEGORIES` now use, so `tsc` refuses a wrong
/// key too), but types do not exist at run time; CI's `gen:api` diff keeps
/// `schema.ts` and the YAML in step.
const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const CONTRACT = readFileSync(join(REPO_ROOT, 'docs/api/openapi.yaml'), 'utf-8')
  // YAML comments out: a key quoted in a comment is not the contract. A `#`
  // only opens a comment at line start or after whitespace, so a `$ref`'s
  // `'#/components/…'` survives.
  .replace(/(^|\s)#.*$/gm, '$1');

/// Every `enum` the contract gives a `category:` property, in flow
/// (`enum: [a, b]`) or block (`- a`) style.
function categoryEnums(yaml: string): string[][] {
  const lines = yaml.split('\n');
  const enums: string[][] = [];
  lines.forEach((line, i) => {
    const key = /^(\s*)category:\s*(.*)$/.exec(line);
    if (!key) return;
    const indent = key[1].length;
    const inline = /enum:\s*\[([^\]]*)\]/.exec(key[2]);
    if (inline) {
      enums.push(splitFlow(inline[1]));
      return;
    }
    // The property's block: the lines indented deeper than its key.
    const block: string[] = [];
    for (let j = i + 1; j < lines.length; j++) {
      const l = lines[j];
      if (l.trim() === '') continue;
      if (l.length - l.trimStart().length <= indent) break;
      block.push(l);
    }
    const at = block.findIndex((l) => /^\s*enum:/.test(l));
    if (at === -1) return;
    const flow = /enum:\s*\[([^\]]*)\]/.exec(block[at]);
    if (flow) {
      enums.push(splitFlow(flow[1]));
      return;
    }
    const enumIndent = block[at].length - block[at].trimStart().length;
    const items: string[] = [];
    for (const l of block.slice(at + 1)) {
      const item = /^(\s*)-\s*(.+?)\s*$/.exec(l);
      if (!item || item[1].length < enumIndent) break;
      items.push(unquote(item[2]));
    }
    enums.push(items);
  });
  return enums;
}

function splitFlow(body: string): string[] {
  return body
    .split(',')
    .map((v) => unquote(v.trim()))
    .filter((v) => v !== '');
}

function unquote(v: string): string {
  return v.replace(/^(['"])(.*)\1$/, '$2');
}

const ENUMS = categoryEnums(CONTRACT);
const API_CATEGORIES = ENUMS[0] ?? [];

describe('the contract’s category values', () => {
  it('are found — an extraction that finds nothing would pass every check below', () => {
    expect(ENUMS.length, 'a category enum in openapi.yaml').toBeGreaterThan(0);
    expect(API_CATEGORIES.length).toBeGreaterThan(0);
  });

  it('are one vocabulary wherever the contract states them', () => {
    // Today only the profile PATCH has an enum. A second one (the response,
    // the filter's parameter) is welcome, as long as it is the same set.
    for (const e of ENUMS) {
      expect([...e].sort()).toEqual([...API_CATEGORIES].sort());
    }
  });
});

describe('the category vocabulary is the API’s', () => {
  it('every category the site asks for is one the API stores', () => {
    for (const c of categoryList) {
      expect(API_CATEGORIES, `« ${c.label} » asks for ${c.apiKey}`).toContain(
        c.apiKey,
      );
    }
  });

  it('every category the API stores has its landing, chip and home link', () => {
    for (const key of API_CATEGORIES) {
      expect(
        categoryList.filter((c) => c.apiKey === key),
        `the site's entry for ${key}`,
      ).toHaveLength(1);
    }
    expect(categoryList).toHaveLength(API_CATEGORIES.length);
  });

  it('a nail salon maps to the onglerie pages', () => {
    // `getLandingParams` reads a salon's stored category through this.
    expect(categorySlugForApiKey('nails')).toBe('onglerie');
  });

  it('the Pro profile offers exactly the API’s categories', () => {
    expect(PROFILE_CATEGORIES.map((c) => c.key).sort()).toEqual(
      [...API_CATEGORIES].sort(),
    );
  });

  it('every category the API stores gets a real label and schema.org type', () => {
    for (const key of API_CATEGORIES) {
      expect(categoryLabelFr(key), `label of ${key}`).not.toBe(
        'Beauté & bien-être',
      );
      const ld = localBusinessJsonLd(
        { ...providerFixture, category: key },
        'https://myweli.com/beaute-divine',
      );
      expect(ld['@type'], `schema.org type of ${key}`).not.toBe(
        'HealthAndBeautyBusiness',
      );
    }
  });
});

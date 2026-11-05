import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

/// **Nothing erasure deletes goes through the image optimizer**
/// (docs/design/web-swiss-cards.md §6, decision 1).
///
/// `images.minimumCacheTTL` is global and 31 days, because cards need it. Consumer
/// erasure really deletes public files, and `/suppression-compte` lists review photos
/// among them, so a resized copy of one in that cache would outlive what a store-linked
/// page says is gone. The property is about which door a file goes through, and only
/// the source records a door: no behavioural test can see a copy in Vercel's cache, and
/// `<Image>` on a review photo would look harmless in review.
///
/// So a new importer of `next/image` is a question this file asks: can what it shows be
/// erased? Salon photos cannot today (§6), which is why they stay.
const ROOTS = ['app', 'components', 'lib'];

const IMPORTERS = [
  'components/FooterMark.tsx',
  'components/Header.tsx',
  'components/pro/AvisClient.tsx',
  'components/pro/ProAuthHeader.tsx',
  'components/provider/BeforeAfterViewer.tsx',
  'components/provider/Gallery.tsx',
  'components/provider/Hero.tsx',
  'components/provider/ProviderCard.tsx',
];

function walk(dir: string, out: string[] = []): string[] {
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else if (/\.(ts|tsx)$/.test(entry)) out.push(full);
  }
  return out;
}

/// Comments are not code: `ProDepositProof.tsx` names `next/image` in one, to say why
/// it does not use it.
function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/^\s*\/\/.*$/gm, '')
    .replace(/\s\/\/\s.*$/gm, '');
}

const IMPORTS_IMAGE = /(from\s+|import\s*\(\s*|require\(\s*|import\s+)['"]next\/image['"]/;

describe('who can put a file in the image cache', () => {
  const files = ROOTS.flatMap((r) => walk(r));

  it('scans a real tree: a pin whose glob matches nothing is green about nothing', () => {
    expect(files.length).toBeGreaterThan(100);
  });

  it('the pattern can see an import, in each spelling', () => {
    expect(IMPORTS_IMAGE.test("import Image from 'next/image';")).toBe(true);
    expect(IMPORTS_IMAGE.test('const I = dynamic(() => import("next/image"));')).toBe(true);
    expect(IMPORTS_IMAGE.test("/// next/image would proxy and cache it")).toBe(false);
  });

  it('the files importing next/image are exactly these, and each new one is asked whether what it shows can be erased', () => {
    const found = files
      .filter((f) => IMPORTS_IMAGE.test(stripComments(readFileSync(f, 'utf8'))))
      .map((f) => f.split(/[\\/]/).join('/'))
      .sort();
    expect(
      found,
      'a file erasure deletes must never enter the optimizer’s cache (web-swiss-cards.md §6): ' +
        'add a new importer here only if what it shows cannot be erased',
    ).toEqual(IMPORTERS);
  });

  it('AvisClient shows review photos with `unoptimized`', () => {
    const src = stripComments(readFileSync('components/pro/AvisClient.tsx', 'utf8'));
    const images = src.match(/<Image\b[\s\S]*?\/>/g) ?? [];
    expect(images.length, 'no <Image> found, so this proves nothing').toBeGreaterThan(0);
    for (const image of images) {
      expect(
        /\bunoptimized\b/.test(image),
        `a review photo is a file erasure deletes, and must never enter the optimizer’s cache:\n${image}`,
      ).toBe(true);
    }
  });
});

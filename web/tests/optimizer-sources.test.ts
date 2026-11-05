import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
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
/// So this holds the door and not only the list. A new importer of `next/image` is a
/// question this file asks: can what it shows be erased? Salon photos cannot today (§6),
/// which is why they stay. A file already on the list cannot start showing something
/// erasure deletes either: the three brand importers show `/brand/` files and nothing
/// else, and no file that reads a review's photos or an avatar reaches the optimizer, by
/// `next/image` itself or by a component that puts what it is given through it.
const NOT_SHIPPED = new Set(['tests', 'tool', 'scripts', 'public']);
/// Build output and tools' own files, wherever they sit.
const NEVER = new Set(['node_modules', 'test-results', 'playwright-report', 'coverage']);
const SOURCE = /\.[cm]?[jt]sx?$/;

/// Every directory of `web/` but those, so a new top-level directory is read the day it
/// arrives. `NOT_SHIPPED` holds at the top level only: `components/provider/tests/` ships.
function walk(root: string): string[] {
  const out: string[] = [];
  const visit = (dir: string) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name.startsWith('.') || NEVER.has(entry.name)) continue;
        if (dir === root && NOT_SHIPPED.has(entry.name)) continue;
        visit(full);
      } else if (SOURCE.test(entry.name)) {
        out.push(relative(root, full).split(/[\\/]/).join('/'));
      }
    }
  };
  visit(root);
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

const IMPORT = String.raw`(?:from\s*|import\s*\(\s*|require\(\s*|import\s*)`;
const IMPORTS_IMAGE = new RegExp(`${IMPORT}['"\`]next/(?:legacy/)?image(?:\\.js)?['"\`]`);
/// The components that put what they are given through the optimizer.
const IMPORTS_A_DOOR = new RegExp(
  `${IMPORT}['"\`][^'"\`]*/(?:Gallery|Hero|BeforeAfterViewer|ProviderCard)(?:\\.[cm]?[jt]sx?)?['"\`]`,
);
/// What erasure deletes: a review's photos (`user_erasure_service.dart:167`) and an avatar (`:181`).
const READS_WHAT_ERASURE_DELETES = /\b(?:photoUrls|avatarUrl)\b/;

/// The attribute switched on: bare, or `{true}`. Reading the word alone stayed green under
/// `unoptimized={false}`, and a variable proves nothing here. Spaces around `=` are still
/// the attribute's value, so `unoptimized = {false}` is not a bare word.
const STAYS_OUT = /\bunoptimized(?:\s*=\s*\{\s*true\s*\}|(?!\s*=))(?=[\s/>])/;

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
const BRAND_IMPORTERS = ['components/FooterMark.tsx', 'components/Header.tsx', 'components/pro/ProAuthHeader.tsx'];
/// The one file that reads what erasure deletes and imports `next/image`: every `<Image>`
/// in it is held to `unoptimized` below.
const THE_EXCEPTION = 'components/pro/AvisClient.tsx';

const read = (file: string) => stripComments(readFileSync(file, 'utf8'));
const imagesIn = (src: string) => src.match(/<Image\b[\s\S]*?\/>/g) ?? [];

describe('who can put a file in the image cache', () => {
  const files = walk('.');

  it('scans a real tree: a pin whose glob matches nothing is green about nothing', () => {
    expect(files.length).toBeGreaterThan(100);
    for (const known of ['app/page.tsx', 'components/provider/ProviderCard.tsx', 'lib/api/account.ts', 'instrumentation.ts']) {
      expect(files, `${known} is not scanned`).toContain(known);
    }
    expect(files.some((f) => /^(tests|tool|scripts|public)\//.test(f)), 'a test tree is being read as shipped code').toBe(false);
  });

  it('the walk reads a new top-level directory and every source extension, and skips what does not ship', () => {
    const root = mkdtempSync(join(tmpdir(), 'optimizer-sources-'));
    try {
      const put = (path: string) => {
        mkdirSync(join(root, path, '..'), { recursive: true });
        writeFileSync(join(root, path), '');
      };
      const shipped = [
        'features/reviews/ReviewPhoto.tsx',
        'app/avis-photos/page.jsx',
        'lib/a.mts',
        'lib/b.cjs',
        'components/provider/tests/inside.tsx',
        'root.ts',
      ];
      for (const path of shipped) put(path);
      for (const path of ['tests/a.tsx', 'tool/b.ts', 'scripts/c.mjs', 'public/d.js', 'node_modules/e/f.js', '.next/g.js', 'lib/h.css']) put(path);
      expect(walk(root).sort()).toEqual([...shipped].sort());
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it('the pattern can see an import, in each spelling', () => {
    for (const spelling of [
      "import Image from 'next/image';",
      "import Image from'next/image';",
      "import Image from 'next/image.js';",
      "import Image from 'next/legacy/image';",
      "import { default as Img } from 'next/image';",
      "export { default } from 'next/image';",
      'const I = dynamic(() => import("next/image"));',
      'const I = dynamic(() => import(`next/image`));',
      "const I = require('next/image');",
    ]) {
      expect(IMPORTS_IMAGE.test(spelling), spelling).toBe(true);
    }
    expect(IMPORTS_IMAGE.test('/// next/image would proxy and cache it')).toBe(false);
  });

  it('the pattern can see a door, and not a type of the same name', () => {
    for (const spelling of [
      "import { Gallery } from './Gallery';",
      "import { Hero } from '../provider/Hero.tsx';",
      "import { BeforeAfterViewer } from '@/components/provider/BeforeAfterViewer';",
      "const C = dynamic(() => import('../provider/ProviderCard').then((m) => m.ProviderCard));",
    ]) {
      expect(IMPORTS_A_DOOR.test(spelling), spelling).toBe(true);
    }
    expect(IMPORTS_A_DOOR.test('"application/json": components["schemas"]["Gallery"];')).toBe(false);
  });

  it('the files importing next/image are exactly these, and each new one is asked whether what it shows can be erased', () => {
    const found = files.filter((f) => IMPORTS_IMAGE.test(read(f))).sort();
    expect(
      found,
      'a file erasure deletes must never enter the optimizer’s cache (web-swiss-cards.md §6): ' +
        'add a new importer here only if what it shows cannot be erased',
    ).toEqual(IMPORTERS);
  });

  it('a brand importer shows the brand’s own files and nothing else', () => {
    for (const file of BRAND_IMPORTERS) {
      const src = read(file);
      // Another name for it would not be read as an `<Image>` below.
      expect(src, `${file}: the import is not the plain one`).toMatch(/^import Image from 'next\/image';$/m);
      const images = imagesIn(src);
      expect(images.length, `${file}: no <Image> found, so this proves nothing`).toBeGreaterThan(0);
      for (const image of images) {
        expect(image, `${file}: an <Image> on anything but a literal /brand/ file:\n${image}`).toMatch(/\ssrc="\/brand\/[^"]+"/);
        expect(image, `${file}: a spread could replace its src:\n${image}`).not.toMatch(/\{\s*\.\.\./);
      }
    }
  });

  it('no file that reads what erasure deletes reaches the optimizer, AvisClient alone excepted', () => {
    const readers = files.filter((f) => READS_WHAT_ERASURE_DELETES.test(read(f)));
    expect(readers, 'the two readers everyone knows are gone, so this proves nothing').toEqual(
      expect.arrayContaining([THE_EXCEPTION, 'components/provider/ReviewList.tsx']),
    );
    const through = readers.filter((f) => {
      const src = read(f);
      return IMPORTS_A_DOOR.test(src) || (f !== THE_EXCEPTION && IMPORTS_IMAGE.test(src));
    });
    expect(
      through,
      'these read a review’s photos or an avatar and can put them through the optimizer: a file erasure ' +
        'deletes must never enter that cache (web-swiss-cards.md §6)',
    ).toEqual([]);
  });

  it('the pattern reads the attribute’s value, not its name', () => {
    expect(STAYS_OUT.test('<Image unoptimized src={a} />')).toBe(true);
    expect(STAYS_OUT.test('<Image src={a} unoptimized />')).toBe(true);
    expect(STAYS_OUT.test('<Image src={a} unoptimized={true} />')).toBe(true);
    expect(STAYS_OUT.test('<Image src={a} unoptimized = {true} />')).toBe(true);
    expect(STAYS_OUT.test('<Image src={a} unoptimized={false} />')).toBe(false);
    expect(STAYS_OUT.test('<Image src={a} unoptimized = {false} />')).toBe(false);
    expect(STAYS_OUT.test('<Image src={a} unoptimized={keep} />')).toBe(false);
    expect(STAYS_OUT.test('<Image src={a} unoptimized = {keep} />')).toBe(false);
  });

  it('AvisClient shows review photos with `unoptimized`', () => {
    const images = imagesIn(read(THE_EXCEPTION));
    expect(images.length, 'no <Image> found, so this proves nothing').toBeGreaterThan(0);
    for (const image of images) {
      expect(
        STAYS_OUT.test(image),
        `a review photo is a file erasure deletes, and must never enter the optimizer’s cache:\n${image}`,
      ).toBe(true);
    }
  });
});

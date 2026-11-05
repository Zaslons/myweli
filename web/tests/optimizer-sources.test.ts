import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, posix, relative } from 'node:path';
import ts from 'typescript';
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
/// else, and no file that reads what erasure deletes reaches the optimizer, by
/// `next/image` itself or by a component that puts what it is given through it, at any
/// number of hops.
///
/// **Every read goes through the compiler's parser.** The first versions read source with
/// regexes, and two spellings walked past them: one `/*` in a `///` comment deleted the
/// import below it, and `<Image …></Image>` ran on to the next `/>`. What this still
/// cannot see is data handed along by a file that names none of the words below: a
/// parent that gets a URL from a helper and gives it to `Gallery` reads no such word.
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

function parse(text: string, name = 'probe.tsx'): ts.SourceFile {
  const kind = /\.[cm]?ts$/.test(name) ? ts.ScriptKind.TS : ts.ScriptKind.TSX;
  return ts.createSourceFile(name, text, ts.ScriptTarget.Latest, true, kind);
}

function everyNode(node: ts.Node, visit: (n: ts.Node) => void): void {
  visit(node);
  node.forEachChild((child) => everyNode(child, visit));
}

/// `import type` is erased at build, so it opens no door.
function erasedAtBuild(node: ts.ImportDeclaration | ts.ExportDeclaration): boolean {
  if (ts.isExportDeclaration(node)) return node.isTypeOnly;
  const clause = node.importClause;
  if (!clause) return false;
  if (clause.isTypeOnly) return true;
  const named = clause.namedBindings;
  return !clause.name && !!named && ts.isNamedImports(named) && named.elements.length > 0 && named.elements.every((e) => e.isTypeOnly);
}

/// Every module the file loads, whichever way it spells that: `import`, `export … from`,
/// `import()`, `require()`, with any quote, in code only.
function modulesLoadedBy(source: ts.SourceFile): string[] {
  const out: string[] = [];
  everyNode(source, (node) => {
    if (ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) {
      if (node.moduleSpecifier && ts.isStringLiteralLike(node.moduleSpecifier) && !erasedAtBuild(node)) {
        out.push(node.moduleSpecifier.text);
      }
    } else if (ts.isImportEqualsDeclaration(node)) {
      const reference = node.moduleReference;
      if (ts.isExternalModuleReference(reference) && ts.isStringLiteralLike(reference.expression)) {
        out.push(reference.expression.text);
      }
    } else if (ts.isCallExpression(node)) {
      const callee = node.expression;
      const loads = callee.kind === ts.SyntaxKind.ImportKeyword || (ts.isIdentifier(callee) && callee.text === 'require');
      const first = node.arguments[0];
      if (loads && first && ts.isStringLiteralLike(first)) out.push(first.text);
    }
  });
  return out;
}

const NEXT_IMAGE = /^next\/(?:legacy\/)?image(?:\.js)?$/;
const loadsNextImage = (source: ts.SourceFile) => modulesLoadedBy(source).some((m) => NEXT_IMAGE.test(m));

/// What erasure deletes: a deposit's screenshot (`user_erasure_service.dart:166`), a
/// review's photos (`:167`) and an avatar (`:179`).
const READS_WHAT_ERASURE_DELETES = /^(?:depositScreenshotUrl|photoUrls|avatarUrl)$/;

/// A name in code, or a key spelled as a string: `r['photoUrls']`. Never a comment or copy.
function readsWhatErasureDeletes(source: ts.SourceFile): boolean {
  let found = false;
  everyNode(source, (node) => {
    if ((ts.isIdentifier(node) || ts.isStringLiteralLike(node)) && READS_WHAT_ERASURE_DELETES.test(node.text)) found = true;
  });
  return found;
}

const TAG = (element: ts.JsxOpeningLikeElement) => element.tagName.getText();

function elementsOf(source: ts.SourceFile, name: string): ts.JsxOpeningLikeElement[] {
  const out: ts.JsxOpeningLikeElement[] = [];
  everyNode(source, (node) => {
    if ((ts.isJsxSelfClosingElement(node) || ts.isJsxOpeningElement(node)) && TAG(node) === name) out.push(node);
  });
  return out;
}

const attribute = (element: ts.JsxOpeningLikeElement, name: string) =>
  element.attributes.properties.find((p): p is ts.JsxAttribute => ts.isJsxAttribute(p) && p.name.getText() === name);
const hasSpread = (element: ts.JsxOpeningLikeElement) => element.attributes.properties.some(ts.isJsxSpreadAttribute);

/// `unoptimized` switched on: bare, or `{true}`. A variable proves nothing here.
function staysOut(element: ts.JsxOpeningLikeElement): boolean {
  const unoptimized = attribute(element, 'unoptimized');
  if (!unoptimized) return false;
  const value = unoptimized.initializer;
  return value === undefined || (ts.isJsxExpression(value) && value.expression?.kind === ts.SyntaxKind.TrueKeyword);
}

/// The one name `next/image` has in a file, from its one plain import, or why not.
function plainImageName(source: ts.SourceFile): string | { not: string } {
  if (modulesLoadedBy(source).filter((m) => NEXT_IMAGE.test(m)).length !== 1) return { not: 'loaded more than once, or not at all' };
  const declaration = source.statements.find(
    (s): s is ts.ImportDeclaration => ts.isImportDeclaration(s) && ts.isStringLiteralLike(s.moduleSpecifier) && NEXT_IMAGE.test(s.moduleSpecifier.text),
  );
  const clause = declaration?.importClause;
  if (!clause?.name || clause.namedBindings) return { not: 'not `import Image from` alone' };
  return clause.name.text;
}

/// Each use of that name that is not a JSX tag: a second name for it, `createElement`, a
/// prop. None of those is read as an element, so none may exist in a file held here.
function usesOtherThanATag(source: ts.SourceFile, name: string): string[] {
  const out: string[] = [];
  everyNode(source, (node) => {
    if (!ts.isIdentifier(node) || node.text !== name) return;
    const parent = node.parent;
    if (ts.isImportClause(parent)) return;
    if ((ts.isJsxOpeningElement(parent) || ts.isJsxSelfClosingElement(parent) || ts.isJsxClosingElement(parent)) && parent.tagName === node) return;
    out.push(parent.getText());
  });
  return out;
}

const EXTENSIONS = ['.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.mts', '.cts'];

/// A file of the tree, from a relative or `@/` path. A package is not in the tree.
function resolveIn(tree: ReadonlySet<string>, from: string, specifier: string): string | null {
  const base = specifier.startsWith('@/')
    ? specifier.slice(2)
    : specifier.startsWith('.')
      ? posix.join(posix.dirname(from), specifier)
      : null;
  if (base === null) return null;
  const candidates = [base, ...EXTENSIONS.map((e) => base + e), ...EXTENSIONS.map((e) => posix.join(base, 'index' + e))];
  return candidates.find((c) => tree.has(c)) ?? null;
}

/// The way from `start` to one of `doors` through what the files load, or null. Each file
/// is read once, so a cycle ends.
function wayToADoor(sources: ReadonlyMap<string, ts.SourceFile>, start: string, doors: readonly string[]): string[] | null {
  const tree = new Set(sources.keys());
  const seen = new Set([start]);
  const queue: string[][] = [[start]];
  while (queue.length > 0) {
    const way = queue.shift()!;
    const here = way[way.length - 1];
    for (const specifier of modulesLoadedBy(sources.get(here)!)) {
      const next = resolveIn(tree, here, specifier);
      if (next === null || seen.has(next)) continue;
      if (doors.includes(next)) return [...way, next];
      seen.add(next);
      queue.push([...way, next]);
    }
  }
  return null;
}

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
/// The components that put what they are given through the optimizer.
const DOORS = IMPORTERS.filter((f) => !BRAND_IMPORTERS.includes(f) && f !== THE_EXCEPTION);

describe('who can put a file in the image cache', () => {
  const files = walk('.');
  const sources = new Map(files.map((f) => [f, parse(readFileSync(f, 'utf8'), f)]));
  const source = (file: string) => sources.get(file)!;

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
        mkdirSync(dirname(join(root, path)), { recursive: true });
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

  it('an import is seen in each spelling, and past a `/*` in a comment or a string', () => {
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
      // A regex for block comments starts at any `/*`, and ate the import below these.
      "/// Read from /api/*.\nimport Image from 'next/image';\nconst a = 1; /* one */",
      "const glob = 'image/*';\nimport Image from 'next/image';\nconst a = 1; /* one */",
    ]) {
      expect(loadsNextImage(parse(spelling)), spelling).toBe(true);
    }
  });

  it('a comment, a string or a type is not an import', () => {
    for (const spelling of [
      '/// next/image would proxy and cache it',
      "// import Image from 'next/image';",
      "/* import Image from 'next/image'; */",
      "const note = \"import Image from 'next/image'\";",
      "import type { ImageProps } from 'next/image';",
      "import { type ImageProps } from 'next/image';",
    ]) {
      expect(loadsNextImage(parse(spelling)), spelling).toBe(false);
    }
  });

  it('a door is reached through a wrapper or a barrel, and a cycle ends', () => {
    const tree = (files: Record<string, string>) =>
      new Map(Object.entries(files).map(([name, text]) => [name, parse(text, name)]));
    const doors = ['components/provider/Gallery.tsx'];
    const gallery = { 'components/provider/Gallery.tsx': "import Image from 'next/image';" };
    expect(wayToADoor(tree({ ...gallery, 'r.tsx': "import { Gallery } from './components/provider/Gallery';" }), 'r.tsx', doors)).toEqual([
      'r.tsx',
      'components/provider/Gallery.tsx',
    ]);
    expect(
      wayToADoor(tree({ ...gallery, 'a/r.tsx': "import { W } from './w';", 'a/w.tsx': "import { Gallery } from '@/components/provider/Gallery';" }), 'a/r.tsx', doors),
      'one hop past the reader',
    ).toEqual(['a/r.tsx', 'a/w.tsx', 'components/provider/Gallery.tsx']);
    expect(
      wayToADoor(tree({ 'components/provider/Gallery.tsx': '', 'components/provider/index.ts': "export { Gallery } from './Gallery';", 'components/provider/r.tsx': "import { Gallery } from '.';" }), 'components/provider/r.tsx', doors),
      'a barrel has no door in its name',
    ).toEqual(['components/provider/r.tsx', 'components/provider/index.ts', 'components/provider/Gallery.tsx']);
    expect(wayToADoor(tree({ ...gallery, 'r.tsx': "import type { G } from './components/provider/Gallery';" }), 'r.tsx', doors), 'a type loads nothing').toBeNull();
    expect(wayToADoor(tree({ ...gallery, 'a.tsx': "import './b';", 'b.tsx': "import './a';" }), 'a.tsx', doors), 'a cycle').toBeNull();
    expect(wayToADoor(tree({ ...gallery, 'r.tsx': "import { Gallery } from 'gallery';" }), 'r.tsx', doors), 'a package of that name').toBeNull();
  });

  it('the files importing next/image are exactly these, and each new one is asked whether what it shows can be erased', () => {
    const found = files.filter((f) => loadsNextImage(source(f))).sort();
    expect(
      found,
      'a file erasure deletes must never enter the optimizer’s cache (web-swiss-cards.md §6): ' +
        'add a new importer here only if what it shows cannot be erased',
    ).toEqual(IMPORTERS);
  });

  it('every element is read, however it is closed, and a second name for the import is refused', () => {
    const closed = parse(`import Image from 'next/image';
      const a = <Image src={avatar} alt="" width={1} height={1}></Image>;
      const b = <Image src="/brand/a.svg" alt="" width={1} height={1} />;`);
    expect(elementsOf(closed, 'Image').length, 'an element closed by </Image> ran on to the next />').toBe(2);
    expect(plainImageName(closed)).toBe('Image');
    expect(usesOtherThanATag(closed, 'Image')).toEqual([]);

    const alias = parse("import Image from 'next/image';\nconst Logo = Image;\nconst a = <Logo src={avatar} />;");
    expect(usesOtherThanATag(alias, 'Image')).toEqual(['Logo = Image']);
    const created = parse("import Image from 'next/image';\nconst a = createElement(Image, { src: avatar });");
    expect(usesOtherThanATag(created, 'Image').length).toBe(1);

    for (const spelling of [
      "import { default as Img } from 'next/image';",
      "import Image, { getImageProps } from 'next/image';",
      "import Image from 'next/image';\nconst Other = require('next/image');",
    ]) {
      expect(typeof plainImageName(parse(spelling)), spelling).toBe('object');
    }
  });

  it('a brand importer shows the brand’s own files and nothing else', () => {
    for (const file of BRAND_IMPORTERS) {
      const name = plainImageName(source(file));
      if (typeof name !== 'string') throw new Error(`${file}: the import is not the plain one: ${name.not}`);
      expect(usesOtherThanATag(source(file), name), `${file}: the import has another use, which is not read as an element`).toEqual([]);
      const images = elementsOf(source(file), name);
      expect(images.length, `${file}: no <Image> found, so this proves nothing`).toBeGreaterThan(0);
      for (const image of images) {
        const value = attribute(image, 'src')?.initializer;
        expect(value && ts.isStringLiteral(value) && value.text.startsWith('/brand/'), `${file}: an <Image> on anything but a literal /brand/ file:\n${image.getText()}`).toBe(true);
        expect(hasSpread(image), `${file}: a spread could replace its src:\n${image.getText()}`).toBe(false);
      }
    }
  });

  it('the word list holds each thing erasure deletes, by name', () => {
    for (const word of ['depositScreenshotUrl', 'photoUrls', 'avatarUrl']) {
      expect(readsWhatErasureDeletes(parse(`const a = r.${word};`)), word).toBe(true);
      expect(readsWhatErasureDeletes(parse(`const a = r['${word}'];`)), `a key spelled as a string: ${word}`).toBe(true);
      expect(readsWhatErasureDeletes(parse(`/// r.${word}\nconst a = <p>${word}</p>;`)), `a comment or copy: ${word}`).toBe(false);
    }
  });

  it('no file that reads what erasure deletes reaches the optimizer, AvisClient alone excepted', () => {
    const readers = files.filter((f) => readsWhatErasureDeletes(source(f)));
    expect(readers, 'the readers everyone knows are gone, so this proves nothing').toEqual(
      expect.arrayContaining([THE_EXCEPTION, 'components/provider/ReviewList.tsx', 'components/account/AppointmentDetailClient.tsx']),
    );
    expect(DOORS.length, 'no door to read').toBe(4);
    const through = readers
      .map((f) => {
        if (f !== THE_EXCEPTION && loadsNextImage(source(f))) return `${f}: next/image itself`;
        const way = wayToADoor(sources, f, DOORS);
        return way ? way.join(' -> ') : null;
      })
      .filter(Boolean);
    expect(
      through,
      'these read what erasure deletes and can put it through the optimizer: a file erasure ' +
        'deletes must never enter that cache (web-swiss-cards.md §6)',
    ).toEqual([]);
  });

  it('`unoptimized` is read by its value, not its name', () => {
    const image = (jsx: string) => elementsOf(parse(`const a = ${jsx};`), 'Image')[0];
    expect(staysOut(image('<Image unoptimized src={a} />'))).toBe(true);
    expect(staysOut(image('<Image src={a} unoptimized />'))).toBe(true);
    expect(staysOut(image('<Image src={a} unoptimized={true} />'))).toBe(true);
    expect(staysOut(image('<Image src={a} unoptimized = {true} />'))).toBe(true);
    expect(staysOut(image('<Image src={a} unoptimized></Image>'))).toBe(true);
    expect(staysOut(image('<Image src={a} />'))).toBe(false);
    expect(staysOut(image('<Image src={a} unoptimized={false} />'))).toBe(false);
    expect(staysOut(image('<Image src={a} unoptimized = {false} />'))).toBe(false);
    expect(staysOut(image('<Image src={a} unoptimized={keep} />'))).toBe(false);
    expect(staysOut(image('<Image src={a} unoptimized = {keep} />'))).toBe(false);
  });

  it('AvisClient shows review photos with `unoptimized`', () => {
    const avis = source(THE_EXCEPTION);
    const name = plainImageName(avis);
    if (typeof name !== 'string') throw new Error(`${THE_EXCEPTION}: the import is not the plain one: ${name.not}`);
    expect(usesOtherThanATag(avis, name), 'the import has another use, which is not read as an element').toEqual([]);
    const images = elementsOf(avis, name);
    expect(images.length, 'no <Image> found, so this proves nothing').toBeGreaterThan(0);
    for (const image of images) {
      expect(staysOut(image), `a review photo is a file erasure deletes, and must never enter the optimizer’s cache:\n${image.getText()}`).toBe(true);
      expect(hasSpread(image), `a spread could switch \`unoptimized\` off:\n${image.getText()}`).toBe(false);
    }
  });
});

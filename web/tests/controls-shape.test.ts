import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { describe, expect, it } from 'vitest';

/// docs/design/web-swiss-fields.md §5: the source half of « anything you type in or
/// press is square, with a thin black line ». The rendered sweep in
/// tests/e2e/controls-shape.spec.ts holds every page it visits; this holds the
/// dialogs and rare states it cannot reach.
const WEB = join(__dirname, '..');
const walk = (dir: string): string[] =>
  readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    return statSync(p).isDirectory() ? walk(p) : /\.tsx?$/.test(name) ? [p] : [];
  });

/// Comments out first: several files explain the old look in prose, and a comment
/// must neither fail this nor satisfy it.
const code = (file: string) =>
  readFileSync(file, 'utf8')
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/^\s*\/\/.*$/gm, '')
    .replace(/\s\/\/ .*$/gm, '');

const SOURCES = ['app', 'components', 'lib'].flatMap((d) => walk(join(WEB, d)));
const classStrings = (file: string) =>
  [...code(file).matchAll(/["'`]([^"'`\n]*)["'`]/g)].map((m) => m[1]);
const where = (file: string, s: string) => `${relative(WEB, file)}: ${s.slice(0, 90)}`;

describe('controls in the source', () => {
  it('found the code it is meant to read', () => {
    expect(SOURCES.length).toBeGreaterThan(100);
    expect(SOURCES.flatMap(classStrings).filter((s) => s.includes('min-h-12')).length).toBeGreaterThan(50);
  });

  it('a class with the 48px floor is a control, so it carries no rounded token', () => {
    const rounded = SOURCES.flatMap((f) =>
      classStrings(f)
        .filter((s) => s.includes('min-h-12') && /\brounded-(sm|md|lg|xl|xxl)\b/.test(s))
        .map((s) => where(f, s)),
    );
    expect(rounded).toEqual([]);
  });

  it('no filled button keeps a rounded token', () => {
    const filled = SOURCES.flatMap((f) =>
      classStrings(f)
        .filter((s) => /\brounded-(sm|md|lg|xl|xxl)\b[^"'`]*\bbg-primary\b(?!\/)/.test(s))
        // Apple's button keeps the shape its brand describes (spec §1).
        .filter(() => !f.endsWith('AppleSignInButton.tsx'))
        .map((s) => where(f, s)),
    );
    expect(filled).toEqual([]);
  });

  // The chips, and the before/after viewer's round handle and dots, on a photo.
  it('the grey control line lives on only in the spec’s exceptions', () => {
    const grey = SOURCES.filter((f) => code(f).includes('border-borderStrong')).map((f) => relative(WEB, f)).sort();
    expect(grey).toEqual(['components/Chip.tsx', 'components/provider/BeforeAfterViewer.tsx']);
  });

  it('the shared pieces use the token, and the phone field does too', () => {
    expect(code(join(WEB, 'components/Button.tsx'))).toContain('rounded-control');
    expect(code(join(WEB, 'components/TextField.tsx'))).toContain('rounded-control');
    const css = readFileSync(join(WEB, 'styles/globals.css'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
    const phone = css.slice(css.indexOf('.myweli-phone .PhoneInputInput {'));
    expect(phone.slice(0, phone.indexOf('}'))).toContain("theme('borderRadius.control')");
    expect(phone.slice(0, phone.indexOf('}'))).toContain("theme('colors.primary')");
  });

  // A field with no radius class would round the moment it was clicked.
  it('the base focus rule does not hand out a radius', () => {
    const css = readFileSync(join(WEB, 'styles/globals.css'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
    const rule = css.slice(css.indexOf(':focus-visible {'));
    expect(rule.slice(0, rule.indexOf('}'))).not.toContain('border-radius');
  });
});

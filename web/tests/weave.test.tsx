import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { WovenBand, WovenPanel } from '../components/brand/Weave';
import { Wordmark } from '../components/brand/Wordmark';

/// docs/design/web-swiss-direction.md §4.3 and §4.6: the rules that keep the
/// pattern calm and honest. They read the markup a visitor is sent, because a
/// rule about what is drawn cannot be held by reading the component's source.
const FORMS = [
  ['panel', renderToStaticMarkup(<WovenPanel />)],
  ['band', renderToStaticMarkup(<WovenBand />)],
] as const;

const BRAND = readFileSync(join(__dirname, '../public/brand/myweli_mark_black.svg'), 'utf8');
const brand = (re: RegExp) => {
  const found = re.exec(BRAND)?.[1];
  expect(found, `the brand file no longer matches ${re}`).toBeTruthy();
  return found as string;
};

describe.each(FORMS)('the %s', (_name, svg) => {
  it('says nothing to a screen reader and holds no text', () => {
    expect(svg).toMatch(/^<svg[^>]* aria-hidden="true"/);
    expect(svg).toMatch(/^<svg[^>]* focusable="false"/);
    expect(svg).not.toMatch(/<text|<title|<desc|aria-label/);
  });

  it('is coloured only through the theme, so a dark version is a value swap', () => {
    expect(svg).not.toMatch(/#[0-9a-f]{3,8}\b/i);
    expect(svg).not.toMatch(/rgba?\(|hsla?\(|style=/);
    expect(svg).toContain('stroke-primary');
  });

  it('does not move', () => {
    expect(svg).not.toMatch(/<animate|<set\b|animate-|transition/);
  });

  it('is one motif: no samplers', () => {
    expect(svg.match(/<pattern/g)).toHaveLength(1);
  });

  it('carries the logo once, exactly as the brand file draws it', () => {
    expect(svg.match(/<path/g)?.length).toBe(2); // the motif's, and the mark's
    expect(svg).toContain(`d="${brand(/ d="([^"]+)"/)}"`);
    expect(svg).toContain(`viewBox="${brand(/viewBox="([^"]+)"/)}"`);
    expect(svg).toContain(`stroke-width="${brand(/stroke-width="([^"]+)"/)}"`);
  });
});

it('the panel’s rows end on its right edge, so they end where the header’s links do', () => {
  const [, svg] = FORMS[0];
  const width = Number(/viewBox="0 0 (\d+)/.exec(svg)?.[1]);
  const ends = [...svg.matchAll(/<rect x="(\d+)" y="\d+" width="(\d+)"/g)].map((m) => Number(m[1]) + Number(m[2]));
  expect(ends.length).toBe(3);
  expect(Math.max(...ends)).toBe(width);
});

it('both forms together stay under 4 KB: every visitor is sent both', () => {
  const bytes = FORMS.reduce((sum, [, svg]) => sum + Buffer.byteLength(svg), 0);
  expect(bytes).toBeLessThanOrEqual(4096);
});

it('each form has its own pattern id: one hidden by CSS must not blank the other', () => {
  const ids = FORMS.map(([, svg]) => /<pattern id="([^"]+)"/.exec(svg)?.[1]);
  expect(new Set(ids).size).toBe(2);
  for (const [, svg] of FORMS) {
    expect(svg).toContain(`url(#${/<pattern id="([^"]+)"/.exec(svg)?.[1]})`);
  }
});

describe('the wordmark is the brand file, placed and not redrawn (§3)', () => {
  const FILE = readFileSync(join(__dirname, '../public/brand/myweli_wordmark_black.svg'), 'utf8');
  const svg = renderToStaticMarkup(<Wordmark />);
  const paths = (markup: string) => [...markup.matchAll(/ d="([^"]+)"/g)].map((m) => m[1]);
  const strokes = (markup: string) => [...markup.matchAll(/stroke-width="([^"]+)"/g)].map((m) => m[1]);

  it('has every path of the file, in order', () => {
    expect(paths(FILE).length).toBeGreaterThan(1);
    expect(paths(svg)).toEqual(paths(FILE));
    expect(strokes(svg)).toEqual(strokes(FILE));
  });

  it('starts where the M’s ink does, and ends and sits where the file does', () => {
    const [x, y, width, height] = (/viewBox="([^"]+)"/.exec(FILE) as RegExpExecArray)[1].split(' ').map(Number);
    const [ownX, ownY, ownWidth, ownHeight] = (/viewBox="([^"]+)"/.exec(svg) as RegExpExecArray)[1].split(' ').map(Number);
    const firstX = Number(/ d="M([\d.]+)/.exec(FILE)?.[1]);
    const stroke = Number(strokes(FILE)[0]);
    expect(ownX).toBeCloseTo(firstX - stroke / 2, 2);
    expect(ownX + ownWidth).toBeCloseTo(x + width, 2);
    expect(ownY).toBe(y);
    expect(ownHeight).toBe(height);
  });

  it('is coloured through the theme and says nothing to a screen reader', () => {
    expect(svg).not.toMatch(/#[0-9a-f]{3,8}\b/i);
    expect(svg).toMatch(/^<svg[^>]* aria-hidden="true"/);
    expect(svg).toContain('stroke-primary');
    expect(svg).toContain('fill-primary');
  });
});

import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import postcss from 'postcss';
import tailwindcss from 'tailwindcss';
import { describe, expect, it } from 'vitest';

import tailwindConfig from '../tailwind.config';

/// docs/design/web-pro-upload-resize.md §9.2 — the upload modules add nothing
/// to the shared stylesheet.
///
/// Tailwind scans `lib/**` (tailwind.config.ts `content`), and it reads
/// comments as well as code: any word that is a utility name becomes a rule in
/// the ONE stylesheet every page loads — the five store-linked pages included,
/// which must not change while Apple reviews the app. Found while building:
/// « failing to shrink a Pro photo » and « the canvas transform » emitted
/// `.shrink` and `.transform` (242 bytes) into a stylesheet that was otherwise
/// byte-identical to `main`'s. These files style nothing, so they must emit
/// nothing.
const FILES = ['lib/image/compress.ts', 'lib/pro/upload.ts', 'lib/pro/upload-hooks.ts', 'lib/upload-telemetry.ts'];

async function utilitiesFrom(raw: string): Promise<string> {
  const config = { ...(tailwindConfig as object), content: [{ raw, extension: 'ts' }] };
  const { css } = await postcss([tailwindcss(config as never)]).process('@tailwind utilities;', {
    from: undefined,
  });
  return css.trim();
}

describe('the upload modules emit no Tailwind class', () => {
  it('the probe can see a class (control)', async () => {
    expect(await utilitiesFrom('// to shrink it, transform it')).toContain('.shrink');
  });

  for (const file of FILES) {
    it(file, async () => {
      const source = readFileSync(join(__dirname, '..', file), 'utf8');
      expect(await utilitiesFrom(source)).toBe('');
    });
  }
});

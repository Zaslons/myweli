import { execFile } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { describe, expect, it } from 'vitest';

/// **The preload that fails the stub's photo host at once** (docs/design/web-swiss-cards.md
/// §8), and the two lines that load it.
///
/// `site-look.spec.ts`'s « test server » case reads the speed, and on a machine whose
/// real lookup of `cdn.stub` fails at once it reads the same with no preload at all
/// (watched: it stayed green). So it cannot say the preload is there, and a CI run that
/// lost its `NODE_OPTIONS` would only stall, on the one machine this exists for. Nothing
/// else in the repo reads those two lines. These do, and they stand in for CI's stall
/// with a lookup that never answers, so the answer does not depend on this machine's DNS.
const PRELOAD = 'tests/e2e/_cdn-stub-dns.cjs';
const FLAG = `--require ./${PRELOAD}`;

const run = promisify(execFile);

/// Each case starts a process, and a loaded runner is slow at that, not at what is read.
const CHILD_LIMIT = 15_000;

/// Runs in its own process, because the preload replaces a property of a builtin.
async function child(body: string): Promise<Record<string, unknown>> {
  const { stdout } = await run(process.execPath, ['-e', body], { timeout: 10_000 });
  return JSON.parse(stdout);
}

/// A `dns.lookup` standing in for CI's: it never answers for `cdn.stub`, and records every
/// host it is asked about. The preload then loads on top of it, as `--require` loads it on
/// top of the real one.
const HANGING_LOOKUP = `
  const dns = require('node:dns');
  const asked = [];
  const real = dns.lookup;
  dns.lookup = function (hostname, options, callback) {
    asked.push(hostname);
    if (hostname === 'cdn.stub') return;
    return real.call(this, hostname, options, callback);
  };
  require('./${PRELOAD}');
`;

const job = (workflow: string, name: string) =>
  workflow.match(new RegExp(`^  ${name}:$[\\s\\S]*?(?=^  \\S[^\\n]*:$|$(?![\\s\\S]))`, 'm'))?.[0] ?? '';

/// YAML's own comment syntax. `stripComments` is JavaScript-shaped and would leave a
/// commented-out `NODE_OPTIONS` standing.
const withoutYamlComments = (yaml: string) => yaml.replace(/^\s*#.*$/gm, '');

const withoutTsComments = (ts: string) => ts.replace(/^\s*\/\/.*$/gm, '');

describe('the preload itself', () => {
  it('answers `fetch` for cdn.stub, where a lookup that never answers would stall it', async () => {
    const out = await child(`${HANGING_LOOKUP}
      const hung = new Promise((r) => setTimeout(() => r('hung'), 3000));
      Promise.race([
        fetch('https://cdn.stub/p1.jpg').then(() => 'answered', (e) => e.cause?.code ?? e.code),
        hung,
      ]).then((outcome) => {
        console.log(JSON.stringify({ outcome, asked }));
        process.exit(0);
      });
    `);
    expect(out.outcome).toBe('ENOTFOUND');
    expect(out.asked, 'the real lookup was asked about the host this exists to refuse').toEqual([]);
  }, CHILD_LIMIT);

  it('leaves every other host to the real lookup', async () => {
    const out = await child(`${HANGING_LOOKUP}
      dns.lookup('localhost', (error, address) => {
        console.log(JSON.stringify({ error: error?.code ?? null, address, asked }));
        process.exit(0);
      });
    `);
    expect(out.error).toBeNull();
    expect(out.address).toEqual(expect.any(String));
    expect(out.asked).toEqual(['localhost']);
  }, CHILD_LIMIT);

  it('keeps what `util.promisify` reads off the real lookup', async () => {
    const out = await child(`
      require('./${PRELOAD}');
      require('node:util').promisify(require('node:dns').lookup)('localhost').then((answer) => {
        console.log(JSON.stringify({ answer }));
        process.exit(0);
      });
    `);
    // Without the real one's symbols, promisify answers a bare address string.
    expect(out.answer).toEqual({ address: expect.any(String), family: expect.any(Number) });
  }, CHILD_LIMIT);
});

describe('the two lines that load it', () => {
  it('names a file that exists, relative to where both run', () => {
    expect(existsSync(PRELOAD), `${PRELOAD} is gone`).toBe(true);
  });

  it('ci.yml sets it on the step that runs Lighthouse, in web/', () => {
    const ci = readFileSync(join('..', '.github', 'workflows', 'ci.yml'), 'utf8');
    const lighthouse = withoutYamlComments(job(ci, 'web-lighthouse'));
    expect(lighthouse, 'no web-lighthouse job in ci.yml').not.toBe('');
    expect(lighthouse).toMatch(/^\s+working-directory: web$/m);
    const step = lighthouse.match(/^\s+run: npm run lhci\n\s+env:\n((?:\s*\n|\s+[A-Z_]+: .*\n?)*)/m);
    expect(step, 'the step that runs `npm run lhci` has no env block').not.toBeNull();
    expect(step![1]).toMatch(new RegExp(`^\\s+NODE_OPTIONS: ${FLAG.replace(/[./]/g, '\\$&')}\\s*$`, 'm'));
  });

  it('playwright.config.ts sets it on the Next server, not the stub', () => {
    const config = withoutTsComments(readFileSync('playwright.config.ts', 'utf8'));
    const next = config.slice(config.indexOf('command: `npm run build && npm run start`'));
    expect(next).toContain(`NODE_OPTIONS: '${FLAG}'`);
    const stub = config.slice(config.indexOf('command: `node tests/e2e/stub-api.mjs`'), config.indexOf('command: `npm run build'));
    expect(stub).not.toBe('');
    expect(stub).not.toContain('NODE_OPTIONS');
  });
});

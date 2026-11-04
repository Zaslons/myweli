import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

/// docs/design/product-questions-batch8.md §2.5 (B8.5, decision 31) — the Pro
/// phone sign-in is gone from the web too. No screen ever used it: two BFF
/// routes and two helpers waited for a server route that opened with the
/// CLIENTS' `AUTH_METHODS` switch, and signed into the first account carrying
/// a number that is no longer unique. The server routes are removed; so is
/// every way the web could reach them.

const ROOT = join(__dirname, '..');

function sources(dir: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...sources(p));
    else if (/\.(ts|tsx)$/.test(name)) out.push(p);
  }
  return out;
}

describe('the Pro phone sign-in (B8.5)', () => {
  it('has no BFF route', () => {
    expect(existsSync(join(ROOT, 'app/api/pro/auth/request-otp'))).toBe(false);
    expect(existsSync(join(ROOT, 'app/api/pro/auth/verify'))).toBe(false);
  });

  it('has no helper and no caller in app/, components/ or lib/', () => {
    const hits = ['app', 'components', 'lib']
      .flatMap((d) => sources(join(ROOT, d)))
      .filter((f) =>
        /requestOtpPro|verifyOtpPro|\/auth\/provider\/otp|\/api\/pro\/auth\/(request-otp|verify)\b/.test(
          readFileSync(f, 'utf8'),
        ),
      );
    expect(hits).toEqual([]);
  });

  it('CONTROL: the clients’ phone helpers are still there', () => {
    const client = readFileSync(join(ROOT, 'lib/api/schema.ts'), 'utf8');
    expect(client).toContain('"/auth/otp/request"');
    expect(client).toContain('"/auth/otp/verify"');
  });
});

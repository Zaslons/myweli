import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { signInMethods } from '../lib/pro/signInMethods';

/// The Pro sign-in's social buttons exist only when their build-time client id
/// does (`/pro/connexion`: Google with NEXT_PUBLIC_GOOGLE_CLIENT_ID, Apple with
/// NEXT_PUBLIC_APPLE_CLIENT_ID; e-mail always). `/pro/suppression-compte` tells
/// a salon which buttons to press, so both read ONE helper: a page that named
/// « Continuer avec Apple » on a build without the Apple id would send people
/// to a button that is not there (docs/design/web-pro-account-deletion.md §5.1,
/// §10 #19).

afterEach(() => {
  vi.unstubAllEnvs();
});

describe('signInMethods()', () => {
  it.each([
    ['both set', 'g.apps.googleusercontent.com', 'com.myweli.signin', true, true],
    ['Google only', 'g.apps.googleusercontent.com', '', true, false],
    ['Apple only', '', 'com.myweli.signin', false, true],
    ['neither', '', '', false, false],
  ])('%s', (_name, google, apple, hasGoogle, hasApple) => {
    vi.stubEnv('NEXT_PUBLIC_GOOGLE_CLIENT_ID', google);
    vi.stubEnv('NEXT_PUBLIC_APPLE_CLIENT_ID', apple);
    const m = signInMethods();
    expect(Boolean(m.google)).toBe(hasGoogle);
    expect(Boolean(m.apple)).toBe(hasApple);
    // The ids themselves, for the sign-in that needs them; an empty variable
    // is no id at all.
    expect(m.google).toBe(google || undefined);
    expect(m.apple).toBe(apple || undefined);
  });

  it('reads the variables literally, so Next inlines them into the build', () => {
    // `process.env[name]` is not inlined in a client bundle: the button would
    // vanish in production while every test here stayed green.
    const src = readFileSync(join(__dirname, '..', 'lib/pro/signInMethods.ts'), 'utf8');
    expect(src).toContain('process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID');
    expect(src).toContain('process.env.NEXT_PUBLIC_APPLE_CLIENT_ID');
  });
});

describe('ProLoginOptions reads its ids only through the helper', () => {
  it('no direct read of either variable, and one call to signInMethods()', () => {
    const src = readFileSync(join(__dirname, '..', 'components/pro/ProLoginOptions.tsx'), 'utf8')
      // Comments may name the variables; code may not.
      .replace(/^\s*\/\/.*$/gm, '');
    expect(src).not.toMatch(/process\.env\.NEXT_PUBLIC_(GOOGLE|APPLE)_CLIENT_ID/);
    expect(src.match(/signInMethods\(\)/g) ?? []).toHaveLength(1);
  });
});

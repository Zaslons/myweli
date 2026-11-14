import { cleanup, render, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

let params: Record<string, string> = {};
const replace = vi.fn();
const routerMock = { replace };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  useSearchParams: () => ({ get: (key: string) => params[key] ?? null }),
}));

import { ProConnexionClient } from '../components/pro/ProConnexionClient';

/// B0.18 (docs/design/web-salon-validation.md §4.5): the decision's e-mail
/// opens `/pro?salon={id}`; signed out, « Aujourd’hui » sends the salon to the
/// login as `?salon=`, and the login lands back on it. Only a salon id is
/// ever read — the address never carries text anywhere.

function signedIn() {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) =>
      String(url) === '/api/pro/me'
        ? new Response(
            JSON.stringify({ account: { id: 'a' }, provider: { id: 'p1', name: 'X' } }),
            { status: 200 },
          )
        : new Response('{}', { status: 404 }),
    ),
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
  params = {};
});

describe('ProConnexionClient — a notice’s salon rides through the login', () => {
  it('?salon=p3 → lands on « Aujourd’hui » of that salon', async () => {
    params = { salon: 'p3' };
    signedIn();
    render(<ProConnexionClient />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro?salon=p3'));
  });

  it('no salon → « Aujourd’hui », as before', async () => {
    signedIn();
    render(<ProConnexionClient />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro'));
  });

  it('anything but a salon id → « Aujourd’hui », never the text', async () => {
    for (const salon of ['../admin', 'p3?x=1', 'https://evil.example', '<b>x</b>', 'a'.repeat(129)]) {
      params = { salon };
      signedIn();
      render(<ProConnexionClient />);
      await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro'));
      expect(replace.mock.calls.flat().join(' '), salon).not.toContain(salon);
      cleanup();
      replace.mockReset();
    }
  });
});

/// B0.19, decision 140 (docs/design/web-pro-account-deletion.md §7, §10 #18):
/// `/pro/suppression-compte`'s « Se connecter à l’Espace Pro » opens
/// `/pro/connexion?suite=profil`, and the sign-in lands on Profil, where
/// « Supprimer mon compte » is. `suite` is a fixed code compared for equality,
/// never a URL: any other value is today's landing, so it is no open redirect.
describe('ProConnexionClient — ?suite=profil lands on Profil', () => {
  it('?suite=profil → /pro/profil', async () => {
    params = { suite: 'profil' };
    signedIn();
    render(<ProConnexionClient />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro/profil'));
  });

  it('any other suite → « Aujourd’hui », never the text', async () => {
    for (const suite of ['https://evil.example', '/pro/profil', '//evil.example', 'Profil', 'profil ', 'profil/x', '']) {
      params = { suite };
      signedIn();
      render(<ProConnexionClient />);
      await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro'));
      if (suite) expect(replace.mock.calls.flat().join(' '), suite).not.toContain(suite);
      expect(replace, suite).not.toHaveBeenCalledWith('/pro/profil');
      cleanup();
      replace.mockReset();
    }
  });

  it('?salon= is unchanged beside it', async () => {
    params = { salon: 'p3', suite: 'autre' };
    signedIn();
    render(<ProConnexionClient />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro?salon=p3'));
  });

  it('the sign-in itself lands there too, not only the already-signed-in forward', async () => {
    // The forward above is `getMyProvider` → 200; a fresh sign-in calls
    // `onSuccess`, which must use the same destination.
    const src = (await import('node:fs')).readFileSync(
      (await import('node:path')).join(__dirname, '..', 'components/pro/ProConnexionClient.tsx'),
      'utf8',
    );
    expect(src).toMatch(/onSuccess=\{\(\) => router\.replace\(home\)\}/);
  });
});

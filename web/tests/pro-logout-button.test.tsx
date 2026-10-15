import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const routerMock = { replace };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
}));

import { ProLogoutButton } from '../components/pro/ProLogoutButton';

/// « Se déconnecter » (the sidebar's, and the rejoin gate's). The session is
/// two httpOnly cookies that only the BFF's logout RESPONSE can clear — so the
/// login page, which looks signed out, is shown only once that response came
/// back OK. A failed call stays where it is and says so: on a shared salon
/// computer, a signed-out-looking screen over a live 30-day session is the
/// next person's way into it.

function stubLogout(answer: () => Promise<Response> | Response) {
  const calls: string[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      calls.push(`${init?.method ?? 'GET'} ${url}`);
      if (url === '/api/pro/auth/logout') return answer();
      return new Response('{}', { status: 404 });
    }),
  );
  return calls;
}

const ok = () => new Response(JSON.stringify({ ok: true }), { status: 200 });

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
});

describe('ProLogoutButton', () => {
  it('the cookies were cleared (200) → the login page', async () => {
    const calls = stubLogout(ok);

    render(<ProLogoutButton />);
    fireEvent.click(screen.getByRole('button', { name: 'Se déconnecter' }));

    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro/connexion'));
    expect(calls).toEqual(['POST /api/pro/auth/logout']);
  });

  it('a host’s landing (the gate’s « accès retiré » banner)', async () => {
    stubLogout(ok);

    render(<ProLogoutButton redirectTo="/pro/connexion?motif=acces-retire" />);
    fireEvent.click(screen.getByRole('button', { name: 'Se déconnecter' }));

    await waitFor(() =>
      expect(replace).toHaveBeenCalledWith('/pro/connexion?motif=acces-retire'),
    );
  });

  it('NO network: stays, « Pas de connexion. Réessayez. », and the button '
    + 'comes back for a retry', async () => {
    stubLogout(() => {
      throw new TypeError('Failed to fetch');
    });

    render(<ProLogoutButton />);
    fireEvent.click(screen.getByRole('button', { name: 'Se déconnecter' }));

    expect(
      (await screen.findByRole('alert')).textContent,
    ).toBe('Pas de connexion. Réessayez.');
    expect(replace).not.toHaveBeenCalled();
    expect(
      (screen.getByRole('button', { name: 'Se déconnecter' }) as HTMLButtonElement)
        .disabled,
    ).toBe(false);
  });

  it('the BFF answered an error (502): stays, with the generic sentence', async () => {
    stubLogout(() => new Response('bad gateway', { status: 502 }));

    render(<ProLogoutButton />);
    fireEvent.click(screen.getByRole('button', { name: 'Se déconnecter' }));

    expect(
      (await screen.findByRole('alert')).textContent,
    ).toBe('Une erreur est survenue. Réessayez.');
    expect(replace).not.toHaveBeenCalled();
  });

  it('a retry that lands signs out, and the message goes', async () => {
    let down = true;
    stubLogout(() => {
      if (down) throw new TypeError('Failed to fetch');
      return ok();
    });

    render(<ProLogoutButton />);
    fireEvent.click(screen.getByRole('button', { name: 'Se déconnecter' }));
    await screen.findByText('Pas de connexion. Réessayez.');

    down = false;
    fireEvent.click(screen.getByRole('button', { name: 'Se déconnecter' }));

    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro/connexion'));
    expect(screen.queryByText('Pas de connexion. Réessayez.')).toBeNull();
  });

  it('`disabled` (an answer is already out on the gate) holds the button', () => {
    stubLogout(ok);

    render(<ProLogoutButton disabled />);

    expect(
      (screen.getByRole('button', { name: 'Se déconnecter' }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);
  });
});

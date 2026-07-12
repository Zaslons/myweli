import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: ProfilClient's load effect depends on [router] — a fresh
// object per render would loop the effect forever.
const routerMock = { replace };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
}));
// MapLibre (LocationPicker) is browser-only — the slim view never mounts it,
// but next/dynamic still resolves the import; stub it out.
vi.mock('next/dynamic', () => ({
  default: () => () => null,
}));

import { ProfilClient } from '../components/pro/ProfilClient';

/// Team access R5b (amended) — the SLIM member Profil: identity + role chip
/// + salon + « Supprimer mon compte » (deletion parity); no salon editor, no
/// export (profile.manage only).

function mockFetch(opts: { deleteStatus?: number } = {}) {
  const calls: { url: string; method: string }[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const method = init?.method ?? 'GET';
      calls.push({ url, method });
      if (url === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc-s', email: 'sonia.staff@equipe.test' },
            provider: { id: 'p1', name: 'Beauté Divine', status: 'active' },
            membership: {
              role: 'staff',
              capabilities: ['journal.manage.own', 'journal.view.own'],
              artistId: 'a1',
              artistName: 'Awa',
            },
          }),
          { status: 200 },
        );
      }
      if (url === '/api/pro/account' && method === 'DELETE') {
        return new Response(null, { status: opts.deleteStatus ?? 204 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
  return calls;
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
});

describe('ProfilClient — slim member view', () => {
  it('staff: identity card, no salon editor, no export', async () => {
    mockFetch();
    render(<ProfilClient />);

    expect(await screen.findByText('sonia.staff@equipe.test')).toBeTruthy();
    expect(screen.getByText('Collaborateur')).toBeTruthy();
    expect(screen.getByText('Salon : Beauté Divine')).toBeTruthy();
    // No salon editor…
    expect(screen.queryByLabelText('Nom du salon')).toBeNull();
    expect(screen.queryByText('Enregistrer')).toBeNull();
    // …and no export (owner-side), but deletion parity stays.
    expect(screen.queryByText('Exporter (JSON)')).toBeNull();
    expect(screen.getByText('Supprimer mon compte')).toBeTruthy();
  });

  it('member deletion: type-SUPPRIMER still calls DELETE /api/pro/account', async () => {
    const calls = mockFetch();
    render(<ProfilClient />);
    fireEvent.click(await screen.findByText('Supprimer mon compte'));
    // The member copy names THEIR account, not the salon.
    expect(screen.getByText(/Votre compte MyWeli Pro sera supprimé/)).toBeTruthy();
    fireEvent.change(screen.getByLabelText('Confirmation de suppression'), {
      target: { value: 'SUPPRIMER' },
    });
    fireEvent.click(screen.getByText('Supprimer définitivement'));

    await waitFor(() =>
      expect(
        calls.some((c) => c.url === '/api/pro/account' && c.method === 'DELETE'),
      ).toBe(true),
    );
    await waitFor(() =>
      expect(replace).toHaveBeenCalledWith('/pro/connexion'),
    );
  });
});

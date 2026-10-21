import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock('next/dynamic', () => ({ default: () => () => null }));
// The read itself rejects — today's `getFavorites` turns every failure into
// status 0, so only a change to it could get here; the page must not wait
// for ever if one does.
vi.mock('../lib/api/account', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../lib/api/account')>()),
  getFavorites: () => Promise.reject(new Error('a read that threw')),
}));

import { RechercheClient } from '../components/discovery/RechercheClient';
import { emptyTree } from '../lib/localities';
import { providerFixture } from './fixtures';

/// docs/design/web-client-polish.md §2.2 (B5.2): a favourites read that
/// THROWS is a failed read too — the hearts are usable and write, never stuck
/// waiting, never the login page.

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('the search ♥ when the favourites read throws', () => {
  it('the heart is usable and writes', async () => {
    const assign = vi.fn();
    vi.stubGlobal('location', { ...window.location, assign, pathname: '/recherche', search: '' });
    const fetchMock = vi.fn(async () => new Response(null, { status: 204 }));
    vi.stubGlobal('fetch', fetchMock);
    render(
      <RechercheClient
        title="Salons"
        results={[providerFixture]}
        q=""
        commune=""
        category=""
        sort="relevance"
        dispo={false}
        tree={emptyTree}
      />,
    );
    const heart = await screen.findByRole('button', { name: /Ajouter .* aux favoris/ });
    await waitFor(() => expect(heart).toBeEnabled());
    fireEvent.click(heart);

    expect(await screen.findByRole('button', { name: /Retirer .* des favoris/ })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    expect(assign).not.toHaveBeenCalled();
  });
});

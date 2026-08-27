import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { MediasClient } from '../components/pro/MediasClient';

/// The ★ control's WIRING (gallery-set-cover.md §8) — the first component
/// test for `MediasClient`. `pro-medias.test.ts` pins the pure helper; this
/// exists because the mutation pass proved that alone cannot see the button:
/// emptying the ★'s onClick left every test green. Same lesson as
/// `pro-disponibilites.test.tsx`, same fetch-stub shape.
const sent: string[][] = [];

function mockFetch() {
  sent.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      if (url === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc-1', email: 'x@salon.test' },
            provider: {
              id: 'p1',
              name: 'Beauté Divine',
              status: 'active',
              imageUrls: ['https://cdn/a.jpg', 'https://cdn/b.jpg', 'https://cdn/c.jpg'],
              beforeAfters: [],
            },
          }),
          { status: 200 },
        );
      }
      if (url === '/api/pro/medias/gallery') {
        const body = JSON.parse(String(init?.body ?? '{}')) as {
          imageUrls?: string[];
        };
        sent.push(body.imageUrls ?? []);
        return new Response('{}', { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('MediasClient — « Définir comme photo principale »', () => {
  it('the ★ stages the promotion and the save carries it', async () => {
    mockFetch();
    render(<MediasClient />);
    await screen.findByText('Couverture');

    const stars = screen.getAllByRole('button', {
      name: 'Définir comme photo principale',
    });
    // Two of three: none on the cover tile.
    expect(stars).toHaveLength(2);
    fireEvent.click(stars[1]); // the tile holding c.jpg
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0]).toEqual([
      'https://cdn/c.jpg',
      'https://cdn/a.jpg',
      'https://cdn/b.jpg',
    ]);
  });
});

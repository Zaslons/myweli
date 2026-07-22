import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const routerMock = { replace, push: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { CatalogueClient } from '../components/pro/CatalogueClient';

/// B7's Catalogue rethreading, review-pinned. The editor renders BELOW the
/// DataTable, so three things main's in-place swap gave for free must be
/// explicit — and each was a review finding:
/// 1. KEYED editor: main keyed the editor per row; unkeyed, switching
///    « Modifier » A→B kept A's form state (useState(initial)) and SAVED IT
///    ONTO B — silent data corruption.
/// 2. The edited row is identifiable (aria-current + tint — DataTable's own
///    test) and the editor names its item in a focused heading.

const SERVICES = [
  { id: 's1', name: 'Tresses', durationMinutes: 60, price: 5000, active: true },
  { id: 's2', name: 'Coupe homme', durationMinutes: 30, price: 3000, active: true },
];

function mockFetch() {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      if (url === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc-1', email: 'x@salon.test' },
            provider: {
              id: 'p1',
              name: 'Beauté Divine',
              status: 'active',
              services: SERVICES,
              artists: [],
            },
          }),
          { status: 200 },
        );
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('CatalogueClient — the below-table editor', () => {
  it('switching Modifier A → B shows B (the keyed editor; unkeyed kept A)', async () => {
    mockFetch();
    render(<CatalogueClient />);

    const buttons = await screen.findAllByRole('button', { name: 'Modifier' });
    fireEvent.click(buttons[0]);
    expect(screen.getByLabelText('Nom du service')).toHaveValue('Tresses');

    fireEvent.click(screen.getAllByRole('button', { name: 'Modifier' })[1]);
    // The unkeyed editor kept 'Tresses' here while saving onto s2.
    expect(screen.getByLabelText('Nom du service')).toHaveValue('Coupe homme');
  });

  it('the editor announces its item: a focused heading naming the service', async () => {
    mockFetch();
    render(<CatalogueClient />);

    fireEvent.click((await screen.findAllByRole('button', { name: 'Modifier' }))[0]);
    const heading = screen.getByRole('heading', { name: 'Modifier « Tresses »' });
    expect(document.activeElement).toBe(heading);
    // And the Modifier button says the panel is open.
    expect(screen.getAllByRole('button', { name: 'Modifier' })[0]).toHaveAttribute(
      'aria-expanded',
      'true',
    );
  });
});

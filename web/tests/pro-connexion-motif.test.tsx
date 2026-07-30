import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

let motif: string | null = null;
vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace: vi.fn() }),
  useSearchParams: () => ({ get: () => motif }),
}));

import { ProConnexionClient } from '../components/pro/ProConnexionClient';

/// Team access R5b — the revoked landing banner on /pro/connexion.

afterEach(() => {
  cleanup();
  motif = null;
});

describe('ProConnexionClient — motif banner', () => {
  it('?motif=acces-retire → the generic revoked banner', () => {
    motif = 'acces-retire';
    render(<ProConnexionClient />);
    expect(
      screen.getByText('Votre accès à ce salon a été retiré.'),
    ).toBeTruthy();
  });

  it('no motif → no banner', () => {
    render(<ProConnexionClient />);
    expect(
      screen.queryByText('Votre accès à ce salon a été retiré.'),
    ).toBeNull();
  });
});

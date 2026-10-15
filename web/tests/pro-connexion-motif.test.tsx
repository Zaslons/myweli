import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

let params: Record<string, string> = {};
vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace: vi.fn() }),
  useSearchParams: () => ({ get: (key: string) => params[key] ?? null }),
}));

import { ProConnexionClient } from '../components/pro/ProConnexionClient';

/// Team access R5b — the revoked landing banner on /pro/connexion. The rejoin
/// gate (docs/design/pro-rejoin-gate.md S3 → S6) adds a `raison`: when the
/// last invitation turned out expired or withdrawn on « Rejoindre », the
/// sign-out carries WHY to the login, as the app's root snack does. Only two
/// fixed codes are read — a URL never injects text.

const EXPIRED = 'Cette invitation a expiré. Demandez au salon de la renvoyer.';
const GONE = 'Introuvable. Actualisez et réessayez.';

afterEach(() => {
  cleanup();
  params = {};
});

describe('ProConnexionClient — motif banner', () => {
  it('?motif=acces-retire → the generic revoked banner', () => {
    params = { motif: 'acces-retire' };
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

  it('&raison=invitation-expiree → the banner AND the app’s expiry sentence',
    () => {
      params = { motif: 'acces-retire', raison: 'invitation-expiree' };
      render(<ProConnexionClient />);
      expect(
        screen.getByText('Votre accès à ce salon a été retiré.'),
      ).toBeTruthy();
      expect(screen.getByText(EXPIRED)).toBeTruthy();
    });

  it('&raison=invitation-introuvable → the « introuvable » sentence', () => {
    params = { motif: 'acces-retire', raison: 'invitation-introuvable' };
    render(<ProConnexionClient />);
    expect(screen.getByText(GONE)).toBeTruthy();
  });

  it('any other raison → the banner alone (no text from the URL)', () => {
    params = { motif: 'acces-retire', raison: '<b>Appelez le 0700000000</b>' };
    render(<ProConnexionClient />);
    expect(
      screen.getByText('Votre accès à ce salon a été retiré.'),
    ).toBeTruthy();
    expect(screen.queryByText(EXPIRED)).toBeNull();
    expect(screen.queryByText(GONE)).toBeNull();
    expect(screen.queryByText(/Appelez/)).toBeNull();
  });

  it('a raison without the motif → nothing', () => {
    params = { raison: 'invitation-expiree' };
    render(<ProConnexionClient />);
    expect(screen.queryByText(EXPIRED)).toBeNull();
  });
});

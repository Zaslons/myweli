import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { InviteMemberDialog } from '../components/pro/InviteMemberDialog';

/// Team access R5a — the 3-step invite dialog. The role summaries are the
/// spec-locked copy; errors run through the shared machine-code table.

function mockInvite(status: number, body: unknown) {
  const calls: { url: string; body: Record<string, unknown> }[] = [];
  const fn = vi.fn(async (url: string, init?: RequestInit) => {
    const b = init?.body ? JSON.parse(init.body as string) : {};
    calls.push({ url, body: b });
    if (url === '/api/pro/members') {
      return new Response(JSON.stringify(body), { status });
    }
    return new Response('{}', { status: 404 });
  });
  vi.stubGlobal('fetch', fn);
  return { fn, calls };
}

const member = {
  id: 'm2',
  providerId: 'p1',
  email: 'awa@salon.test',
  role: 'manager',
  status: 'invited',
  invitedAt: '2026-07-12T09:00:00.000Z',
  expiresAt: '2026-07-19T09:00:00.000Z',
  resendsLeft: 3,
};

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function renderDialog(overrides: Record<string, unknown> = {}) {
  const onInvited = vi.fn();
  const onClose = vi.fn();
  render(
    <InviteMemberDialog
      providerId="p1"
      artists={[{ id: 'a1', name: 'Awa' }]}
      onArtistCreated={vi.fn()}
      onClose={onClose}
      onInvited={onInvited}
      {...overrides}
    />,
  );
  return { onInvited, onClose };
}

describe('InviteMemberDialog', () => {
  it('shows the three role summaries (spec-locked)', () => {
    renderDialog();
    expect(screen.getByText(/Ne voit pas les revenus/)).toBeTruthy();
    expect(screen.getByText(/Pas de catalogue ni de réglages/)).toBeTruthy();
    expect(screen.getByText(/Voit uniquement son propre planning/)).toBeTruthy();
  });

  it('email + role → invite → onInvited with the lowercased email', async () => {
    const { calls } = mockInvite(201, member);
    const { onInvited } = renderDialog();

    fireEvent.change(screen.getByPlaceholderText('collaborateur@exemple.com'), {
      target: { value: 'AWA@Salon.test' },
    });
    fireEvent.click(screen.getByRole('button', { name: /^Manager/ }));
    fireEvent.click(
      screen.getByRole('button', { name: 'Envoyer l’invitation' }),
    );

    await waitFor(() => expect(onInvited).toHaveBeenCalled());
    expect(calls[0].body).toMatchObject({
      email: 'awa@salon.test',
      role: 'manager',
    });
  });

  it('a Collaborateur must pick a fiche → artist_required copy', async () => {
    mockInvite(201, member);
    renderDialog();
    fireEvent.change(screen.getByPlaceholderText('collaborateur@exemple.com'), {
      target: { value: 'staff@salon.test' },
    });
    fireEvent.click(screen.getByRole('button', { name: /^Collaborateur/ }));
    fireEvent.click(
      screen.getByRole('button', { name: 'Envoyer l’invitation' }),
    );
    expect(
      await screen.findByText('Choisissez la fiche employé du collaborateur.'),
    ).toBeTruthy();
  });

  it('member_exists → the shared French copy', async () => {
    mockInvite(409, { error: 'member_exists' });
    renderDialog();
    fireEvent.change(screen.getByPlaceholderText('collaborateur@exemple.com'), {
      target: { value: 'dup@salon.test' },
    });
    fireEvent.click(screen.getByRole('button', { name: /^Manager/ }));
    fireEvent.click(
      screen.getByRole('button', { name: 'Envoyer l’invitation' }),
    );
    expect(
      await screen.findByText('Cette personne est déjà dans l’équipe.'),
    ).toBeTruthy();
  });

  it('offer_required → copy + the picker CTA', async () => {
    mockInvite(409, { error: 'offer_required' });
    renderDialog();
    fireEvent.change(screen.getByPlaceholderText('collaborateur@exemple.com'), {
      target: { value: 'x@salon.test' },
    });
    fireEvent.click(screen.getByRole('button', { name: /^Réception/ }));
    fireEvent.click(
      screen.getByRole('button', { name: 'Envoyer l’invitation' }),
    );
    expect(
      await screen.findByText(
        'Choisissez d’abord votre offre pour inviter votre équipe.',
      ),
    ).toBeTruthy();
    const cta = screen.getByRole('link', { name: 'Choisir mon offre' });
    expect(cta.getAttribute('href')).toBe('/pro/abonnement');
  });
});

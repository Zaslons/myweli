import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { ProInvitationsCard } from '../components/pro/ProInvitationsCard';
import type { TeamInvitation } from '../lib/pro/team';

/// The invitations card (team access R5a), as the rejoin gate reuses it
/// (docs/design/pro-rejoin-gate.md §3–§4): the host can hand it the list it
/// already holds, it tells the host when the last card goes, it removes a card
/// the server says is gone (as the app does), and no failed request — a
/// refusal or no network at all — can leave its buttons disabled for good.

const INV_A: TeamInvitation = {
  id: 'inv-a',
  providerId: 'p1',
  salonName: 'Beauté Divine',
  role: 'staff',
  roleLabel: 'Collaborateur',
  expiresAt: '2099-01-01T00:00:00.000Z',
};
const INV_B: TeamInvitation = {
  id: 'inv-b',
  providerId: 'p2',
  salonName: 'Institut Belle Vue',
  role: 'reception',
  roleLabel: 'Réception',
  expiresAt: '2099-01-01T00:00:00.000Z',
};

type Handler = (init?: RequestInit) => Promise<Response> | Response;

function mockFetch(routes: Record<string, Handler>) {
  const calls: string[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      calls.push(`${init?.method ?? 'GET'} ${url}`);
      const handler = routes[url];
      if (handler) return handler(init);
      return new Response('{}', { status: 404 });
    }),
  );
  return calls;
}

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status });

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('ProInvitationsCard', () => {
  it('`initial` renders the host’s list and skips the fetch', async () => {
    const calls = mockFetch({
      '/api/pro/invitations': () => json(200, { invitations: [] }),
    });

    render(<ProInvitationsCard initial={[INV_A]} />);

    expect(screen.getByText(/vous\s+invite comme Collaborateur/)).toBeTruthy();
    // Give any stray effect a chance to fire before asserting its absence.
    await new Promise((r) => setTimeout(r, 0));
    expect(calls).not.toContain('GET /api/pro/invitations');
  });

  it('Refuser is a 48px text Button, not a bare underlined link', () => {
    mockFetch({});
    render(<ProInvitationsCard initial={[INV_A]} />);
    const refuse = screen.getByRole('button', { name: 'Refuser' });
    expect(refuse.className).toContain('min-h-12');
  });

  it('declining the LAST card calls onEmptied (once), and not before', async () => {
    mockFetch({
      '/api/pro/invitations/inv-a/decline': () => json(200, { declined: true }),
      '/api/pro/invitations/inv-b/decline': () => json(200, { declined: true }),
    });
    const onEmptied = vi.fn();

    render(<ProInvitationsCard initial={[INV_A, INV_B]} onEmptied={onEmptied} />);

    fireEvent.click(screen.getAllByRole('button', { name: 'Refuser' })[0]);
    await waitFor(() =>
      expect(screen.queryByText(/invite comme Collaborateur/)).toBeNull(),
    );
    expect(onEmptied).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole('button', { name: 'Refuser' }));
    await waitFor(() => expect(onEmptied).toHaveBeenCalledTimes(1));
  });

  it('accept → onAccepted(inv), never onEmptied — even on the last card', async () => {
    mockFetch({
      '/api/pro/invitations/inv-a/accept': () =>
        json(200, { id: 'inv-a', status: 'active' }),
    });
    const onAccepted = vi.fn();
    const onEmptied = vi.fn();

    render(
      <ProInvitationsCard
        initial={[INV_A]}
        onAccepted={onAccepted}
        onEmptied={onEmptied}
      />,
    );
    fireEvent.click(screen.getByRole('button', { name: 'Rejoindre' }));

    await waitFor(() => expect(onAccepted).toHaveBeenCalledWith(INV_A));
    expect(onEmptied).not.toHaveBeenCalled();
  });

  it('accept 409 invitation_expired removes the card with the app’s message; '
    + 'the last one empties the list', async () => {
    mockFetch({
      '/api/pro/invitations/inv-a/accept': () =>
        json(409, { error: 'invitation_expired' }),
    });
    const onEmptied = vi.fn();

    render(<ProInvitationsCard initial={[INV_A]} onEmptied={onEmptied} />);
    fireEvent.click(screen.getByRole('button', { name: 'Rejoindre' }));

    expect(
      await screen.findByText(
        'Cette invitation a expiré. Demandez au salon de la renvoyer.',
      ),
    ).toBeTruthy();
    expect(screen.queryByText(/invite comme Collaborateur/)).toBeNull();
    expect(onEmptied).toHaveBeenCalledTimes(1);
  });

  it('accept 404 not_found removes that card only; the others stay', async () => {
    mockFetch({
      '/api/pro/invitations/inv-a/accept': () =>
        json(404, { error: 'not_found' }),
    });
    const onEmptied = vi.fn();

    render(<ProInvitationsCard initial={[INV_A, INV_B]} onEmptied={onEmptied} />);
    fireEvent.click(screen.getAllByRole('button', { name: 'Rejoindre' })[0]);

    expect(
      await screen.findByText('Introuvable. Actualisez et réessayez.'),
    ).toBeTruthy();
    expect(screen.queryByText(/invite comme Collaborateur/)).toBeNull();
    expect(screen.getByText(/invite comme Réception/)).toBeTruthy();
    expect(onEmptied).not.toHaveBeenCalled();
  });

  it('accept 403 forbidden → the invitee’s sentence, not the owner’s; the card stays', async () => {
    mockFetch({
      '/api/pro/invitations/inv-a/accept': () =>
        json(403, { error: 'forbidden' }),
    });

    render(<ProInvitationsCard initial={[INV_A]} />);
    fireEvent.click(screen.getByRole('button', { name: 'Rejoindre' }));

    expect(
      await screen.findByText('Invitation impossible à accepter.'),
    ).toBeTruthy();
    expect(
      screen.queryByText('Action réservée au propriétaire du salon.'),
    ).toBeNull();
    expect(screen.getByText(/invite comme Collaborateur/)).toBeTruthy();
  });

  it('accept with NO network: « Pas de connexion. Réessayez. », the card '
    + 'stays and the buttons come back', async () => {
    mockFetch({
      '/api/pro/invitations/inv-a/accept': () => {
        throw new TypeError('Failed to fetch');
      },
    });
    const onEmptied = vi.fn();

    render(<ProInvitationsCard initial={[INV_A]} onEmptied={onEmptied} />);
    fireEvent.click(screen.getByRole('button', { name: 'Rejoindre' }));

    expect(await screen.findByText('Pas de connexion. Réessayez.')).toBeTruthy();
    expect(screen.getByText(/invite comme Collaborateur/)).toBeTruthy();
    await waitFor(() =>
      expect(
        (screen.getByRole('button', { name: 'Rejoindre' }) as HTMLButtonElement)
          .disabled,
      ).toBe(false),
    );
    expect(
      (screen.getByRole('button', { name: 'Refuser' }) as HTMLButtonElement)
        .disabled,
    ).toBe(false);
    expect(onEmptied).not.toHaveBeenCalled();
  });

  it('decline with NO network is not stuck either', async () => {
    mockFetch({
      '/api/pro/invitations/inv-a/decline': () => {
        throw new TypeError('Failed to fetch');
      },
    });

    render(<ProInvitationsCard initial={[INV_A]} />);
    fireEvent.click(screen.getByRole('button', { name: 'Refuser' }));

    expect(await screen.findByText('Pas de connexion. Réessayez.')).toBeTruthy();
    await waitFor(() =>
      expect(
        (screen.getByRole('button', { name: 'Refuser' }) as HTMLButtonElement)
          .disabled,
      ).toBe(false),
    );
  });

  it('a refused decline → « Refus impossible. », the card stays', async () => {
    mockFetch({
      '/api/pro/invitations/inv-a/decline': () =>
        json(403, { error: 'forbidden' }),
    });

    render(<ProInvitationsCard initial={[INV_A]} />);
    fireEvent.click(screen.getByRole('button', { name: 'Refuser' }));

    expect(await screen.findByText('Refus impossible.')).toBeTruthy();
    expect(screen.getByText(/invite comme Collaborateur/)).toBeTruthy();
  });

  // --- review fixes (docs/design/pro-rejoin-gate.md §10) -------------------

  it('declining one card of two moves focus to the card now in front — its '
    + '« Rejoindre », described by its own sentence — never to <body>', async () => {
    mockFetch({
      '/api/pro/invitations/inv-a/decline': () => json(200, { declined: true }),
    });

    render(<ProInvitationsCard initial={[INV_A, INV_B]} />);
    const refuse = screen.getAllByRole('button', { name: 'Refuser' })[0];
    refuse.focus();
    fireEvent.click(refuse);

    await waitFor(() =>
      expect(screen.queryByText(/invite comme Collaborateur/)).toBeNull(),
    );
    const join = screen.getByRole('button', { name: 'Rejoindre' });
    await waitFor(() => expect(document.activeElement).toBe(join));
    // A screen reader hears where it now is: the remaining card's sentence.
    const describedBy = join.getAttribute('aria-describedby') ?? '';
    expect(describedBy).not.toBe('');
    const description = describedBy
      .split(' ')
      .map((id) => document.getElementById(id)?.textContent ?? '')
      .join(' ');
    expect(description).toMatch(/Institut Belle Vue\s+vous\s+invite comme Réception/);
  });

  it('the LAST card of the list removed (S3, not the last invitation): focus '
    + 'goes back to the previous card', async () => {
    mockFetch({
      '/api/pro/invitations/inv-b/accept': () =>
        json(409, { error: 'invitation_expired' }),
    });

    render(<ProInvitationsCard initial={[INV_A, INV_B]} />);
    const joinB = screen.getAllByRole('button', { name: 'Rejoindre' })[1];
    joinB.focus();
    fireEvent.click(joinB);

    await waitFor(() =>
      expect(screen.queryByText(/invite comme Réception/)).toBeNull(),
    );
    await waitFor(() =>
      expect(document.activeElement).toBe(
        screen.getByRole('button', { name: 'Rejoindre' }),
      ),
    );
  });

  it('a 401 (the session died) goes to the host — no invitation sentence',
    async () => {
      mockFetch({
        '/api/pro/invitations/inv-a/accept': () =>
          json(401, { error: 'not_authenticated' }),
        '/api/pro/invitations/inv-b/decline': () =>
          json(401, { error: 'session_expired' }),
      });
      const onUnauthenticated = vi.fn();

      render(
        <ProInvitationsCard
          initial={[INV_A, INV_B]}
          onUnauthenticated={onUnauthenticated}
        />,
      );
      fireEvent.click(screen.getAllByRole('button', { name: 'Rejoindre' })[0]);
      await waitFor(() => expect(onUnauthenticated).toHaveBeenCalledTimes(1));
      expect(screen.queryByText('Invitation impossible à accepter.')).toBeNull();

      fireEvent.click(screen.getAllByRole('button', { name: 'Refuser' })[1]);
      await waitFor(() => expect(onUnauthenticated).toHaveBeenCalledTimes(2));
      expect(screen.queryByText('Refus impossible.')).toBeNull();
    });

  it('the last card gone because the server said so → onEmptied says why '
    + '(the sign-out carries it to the login)', async () => {
    mockFetch({
      '/api/pro/invitations/inv-a/accept': () =>
        json(409, { error: 'invitation_expired' }),
      '/api/pro/invitations/inv-b/accept': () =>
        json(404, { error: 'not_found' }),
    });
    const expired = vi.fn();
    const gone = vi.fn();

    const { unmount } = render(
      <ProInvitationsCard initial={[INV_A]} onEmptied={expired} />,
    );
    fireEvent.click(screen.getByRole('button', { name: 'Rejoindre' }));
    await waitFor(() =>
      expect(expired).toHaveBeenCalledWith('invitation_expired'),
    );
    unmount();

    render(<ProInvitationsCard initial={[INV_B]} onEmptied={gone} />);
    fireEvent.click(screen.getByRole('button', { name: 'Rejoindre' }));
    await waitFor(() => expect(gone).toHaveBeenCalledWith('not_found'));
  });

  it('declining the last card → onEmptied with no reason', async () => {
    mockFetch({
      '/api/pro/invitations/inv-a/decline': () => json(200, { declined: true }),
    });
    const onEmptied = vi.fn();

    render(<ProInvitationsCard initial={[INV_A]} onEmptied={onEmptied} />);
    fireEvent.click(screen.getByRole('button', { name: 'Refuser' }));

    await waitFor(() => expect(onEmptied).toHaveBeenCalledTimes(1));
    expect(onEmptied.mock.calls[0][0]).toBeUndefined();
  });

  it('tells the host while an answer is out (the gate holds its « Se '
    + 'déconnecter »), and `disabled` holds every button', async () => {
    let release: () => void = () => {};
    mockFetch({
      '/api/pro/invitations/inv-a/accept': () =>
        new Promise((resolve) => {
          release = () => resolve(json(409, { error: 'invitation_expired' }));
        }),
    });
    const onBusyChange = vi.fn();

    const { rerender } = render(
      <ProInvitationsCard
        initial={[INV_A, INV_B]}
        onBusyChange={onBusyChange}
      />,
    );
    fireEvent.click(screen.getAllByRole('button', { name: 'Rejoindre' })[0]);
    await waitFor(() => expect(onBusyChange).toHaveBeenLastCalledWith(true));
    release();
    await waitFor(() => expect(onBusyChange).toHaveBeenLastCalledWith(false));

    rerender(<ProInvitationsCard initial={[INV_A, INV_B]} disabled />);
    for (const b of screen.getAllByRole('button')) {
      expect((b as HTMLButtonElement).disabled).toBe(true);
    }
  });

  it('without `initial` it still loads its own list (the « Aujourd’hui » card)', async () => {
    mockFetch({
      '/api/pro/invitations': () => json(200, { invitations: [INV_B] }),
    });

    render(<ProInvitationsCard />);

    expect(await screen.findByText(/invite comme Réception/)).toBeTruthy();
  });
});

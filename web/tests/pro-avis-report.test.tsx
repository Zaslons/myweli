import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { AvisClient } from '../components/pro/AvisClient';

/// docs/design/backend-integrity-batch6.md §2.6 (B6.6, decision 20) — the
/// salon reports a review of its own salon: App Store 1.2 asks for a way to
/// report user content, and the « Avis » page had none. The client's words
/// and shape; the Propriétaire and the Gérant only (`profile.manage`).

const REVIEW = {
  id: 'r1',
  rating: 1,
  text: 'Injurieux',
  userName: 'Kouassi',
  createdAt: '2026-10-01T10:00:00.000Z',
};
const OWNER = { role: 'owner', capabilities: ['profile.manage', 'finances.view'] };
const MANAGER = { role: 'manager', capabilities: ['profile.manage'] };
const RECEPTION = { role: 'reception', capabilities: ['journal.view.all'] };

const posted: { url: string; body: unknown }[] = [];

function stub(
  membership: unknown,
  report: { status: number } | 'throw' = { status: 200 },
) {
  posted.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      if ((init?.method ?? 'GET') === 'POST') {
        posted.push({ url: u, body: JSON.parse(String(init?.body ?? '{}')) });
        if (report === 'throw') throw new TypeError('Failed to fetch');
        return new Response(JSON.stringify(report.status === 200 ? { status: 'reported' } : { error: 'x' }), {
          status: report.status,
        });
      }
      if (u === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc' },
            provider: { id: 'p1', name: 'Beauté Divine' },
            membership,
          }),
          { status: 200 },
        );
      }
      if (u.startsWith('/api/pro/reviews')) {
        return new Response(
          JSON.stringify({ items: [REVIEW], page: 1, pageSize: 50, total: 1 }),
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
  routerMock.replace.mockReset();
});

async function openAndSend(reason?: string) {
  fireEvent.click(await screen.findByRole('button', { name: 'Signaler' }));
  if (reason) {
    fireEvent.change(screen.getByLabelText('Raison du signalement'), {
      target: { value: reason },
    });
  }
  const buttons = screen.getAllByRole('button', { name: 'Signaler' });
  fireEvent.click(buttons[buttons.length - 1]);
}

describe('« Avis » — the salon reports a review', () => {
  for (const [who, m] of [
    ['the owner', OWNER],
    ['the Gérant', MANAGER],
    ['a legacy owner (no membership block)', undefined],
  ] as const) {
    it(`${who}: « Signaler », a reason, sent — « Merci. Notre équipe va examiner cet avis. »`, async () => {
      stub(m);
      render(<AvisClient />);
      await openAndSend('Insultes');

      expect(
        await screen.findByText('Merci. Notre équipe va examiner cet avis.'),
      ).toBeInTheDocument();
      expect(posted).toEqual([
        { url: '/api/pro/reviews/r1/report', body: { reason: 'Insultes' } },
      ]);
    });
  }

  it('the Réception and the Collaborateur see no « Signaler »', async () => {
    stub(RECEPTION);
    render(<AvisClient />);
    await screen.findByText('Injurieux');
    expect(screen.queryByRole('button', { name: 'Signaler' })).toBeNull();
  });

  it('a refusal → « Le signalement a échoué. Réessayez. », the form stays', async () => {
    stub(OWNER, { status: 500 });
    render(<AvisClient />);
    await openAndSend();
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Le signalement a échoué. Réessayez.',
    );
    expect(screen.getByLabelText('Raison du signalement')).toBeInTheDocument();
  });

  it('no answer → « Pas de connexion. Réessayez. »', async () => {
    stub(OWNER, 'throw');
    render(<AvisClient />);
    await openAndSend();
    expect(await screen.findByRole('alert')).toHaveTextContent('Pas de connexion. Réessayez.');
  });

  it('the session died → the login', async () => {
    stub(OWNER, { status: 401 });
    render(<AvisClient />);
    await openAndSend();
    await waitFor(() => expect(routerMock.replace).toHaveBeenCalledWith('/pro/connexion'));
  });

  it('« Annuler » closes the form, nothing sent', async () => {
    stub(OWNER);
    render(<AvisClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Signaler' }));
    fireEvent.click(screen.getByRole('button', { name: 'Annuler' }));
    expect(screen.queryByLabelText('Raison du signalement')).toBeNull();
    expect(posted).toEqual([]);
  });
});

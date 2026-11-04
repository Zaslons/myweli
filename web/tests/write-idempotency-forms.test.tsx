import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn(), back: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/',
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock('@sentry/nextjs', () => ({ captureMessage: vi.fn() }));

import { BookingFlow } from '../components/booking/BookingFlow';
import { ClientCardClient } from '../components/pro/ClientCardClient';
import { InviteMemberDialog } from '../components/pro/InviteMemberDialog';
import { ManualBookingDialog } from '../components/pro/ManualBookingDialog';
import type { ProProfile } from '../lib/api/pro';
import type { SalonClientCard } from '../lib/pro/clients';
import { providerFixture } from './fixtures';

/// docs/design/write-idempotency.md §4–§8 on the four forms: one key per
/// submission — the SAME on « Réessayer », a new one once the form changed or
/// after a success; a lost answer asked again at once, without a word; and
/// the client's booking lost twice says « Pas de connexion. Réessayez. », the
/// one new wording (Q4). « La réservation a échoué. Réessayez. » stays for a
/// real refusal.

type Answer = 'throw' | { status: number; body?: unknown; raw?: string };

/// One write's answers, in order (the last repeats); every other URL is
/// answered by [rest]. Records the key each write carried.
function server(write: string, answers: Answer[], rest: (url: string) => Answer | undefined) {
  const keys: (string | null)[] = [];
  const bodies: unknown[] = [];
  let i = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      const method = init?.method ?? 'GET';
      let a: Answer | undefined;
      if (`${method} ${u.split('?')[0]}` === write) {
        keys.push(new Headers(init?.headers).get('Idempotency-Key'));
        bodies.push(init?.body ? JSON.parse(String(init.body)) : undefined);
        a = answers[Math.min(i, answers.length - 1)];
        i += 1;
      } else {
        a = rest(u);
      }
      if (a === 'throw') throw new TypeError('Failed to fetch');
      if (!a) return new Response('{}', { status: 404 });
      return new Response(a.raw ?? JSON.stringify(a.body ?? {}), { status: a.status });
    }),
  );
  return { keys, bodies };
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

const KEY = /^[A-Za-z0-9_-]{8,128}$/;

describe('« Confirmer la réservation » (the client)', () => {
  const SLOT = '2099-01-15T14:30:00.000Z';
  const ME = { id: 'u1', name: 'Awa', email: 'awa@x.ci', phoneNumber: '+2250707123456' };
  const booked = { ok: true, appointment: { id: 'a1', status: 'pending', depositAmount: 5000 } };

  async function openConfirm(answers: Answer[]) {
    const s = server('POST /api/bookings', answers, (u) => {
      if (u.startsWith('/api/availability')) return { status: 200, body: { slots: [SLOT] } };
      if (u === '/api/me') return { status: 200, body: ME };
      if (u.startsWith('/api/localities')) return { status: 200, body: { countries: [] } };
      return undefined;
    });
    render(<BookingFlow provider={providerFixture} prefillServiceIds={['s1']} />);
    fireEvent.click(await screen.findByRole('button', { name: /^\d{2}:\d{2}$/ }));
    fireEvent.click(screen.getAllByRole('button', { name: 'Confirmer' })[0]);
    await screen.findByLabelText('Numéro de téléphone');
    const submit = () =>
      fireEvent.click(screen.getByRole('button', { name: 'Confirmer la réservation' }));
    return { ...s, submit };
  }

  it('the answer lost once: asked again with the same key → « Réservation envoyée ✓ », WITH the deposit', async () => {
    const { keys, submit } = await openConfirm(['throw', { status: 201, body: booked }]);
    submit();
    expect(await screen.findByText('Réservation envoyée ✓')).toBeInTheDocument();
    expect(screen.getByLabelText('Capture du paiement')).toBeInTheDocument();
    expect(keys).toHaveLength(2);
    expect(keys[0]).toMatch(KEY);
    expect(keys[1]).toBe(keys[0]);
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('a 2xx whose body was lost: asked again → the deposit block, not a bare « envoyée »', async () => {
    const { keys, submit } = await openConfirm([
      { status: 201, raw: '{"ok":true,' },
      { status: 201, body: booked },
    ]);
    submit();
    expect(await screen.findByText('Réservation envoyée ✓')).toBeInTheDocument();
    expect(screen.getByLabelText('Capture du paiement')).toBeInTheDocument();
    expect(keys[1]).toBe(keys[0]);
  });

  it('lost twice: « Pas de connexion. Réessayez. » — and the retry sends the SAME key', async () => {
    const { keys, submit } = await openConfirm(['throw']);
    submit();
    expect(await screen.findByRole('alert')).toHaveTextContent('Pas de connexion. Réessayez.');
    expect(screen.queryByText(/La réservation a échoué/)).toBeNull();
    expect(keys).toHaveLength(2);
    submit();
    await waitFor(() => expect(keys).toHaveLength(4));
    expect(new Set(keys).size).toBe(1);
  });

  it('a real refusal keeps its own sentence', async () => {
    const { submit } = await openConfirm([{ status: 500, body: { error: 'internal' } }]);
    submit();
    expect(await screen.findByRole('alert')).toHaveTextContent('La réservation a échoué. Réessayez.');
  });

  it('the form changed after a failure (the note): a NEW key — it is a new request', async () => {
    const { keys, submit } = await openConfirm(['throw']);
    submit();
    await screen.findByRole('alert');
    fireEvent.change(screen.getByLabelText('Notes (optionnelles)'), {
      target: { value: 'Cheveux longs' },
    });
    submit();
    await waitFor(() => expect(keys).toHaveLength(4));
    expect(keys[2]).not.toBe(keys[0]);
    expect(keys[3]).toBe(keys[2]);
  });
});

describe('« Créer » (the salon’s booking)', () => {
  const PROFILE = {
    account: { id: 'acc-1', email: 'x@salon.test' },
    provider: {
      id: 'p1',
      name: 'Beauté Divine',
      status: 'active',
      timezone: 'Africa/Abidjan',
      currency: 'XOF',
      services: [
        { id: 's1', name: 'Tresses', description: '', price: 15000, durationMinutes: 120, providerId: 'p1', active: true },
      ],
    },
  } as unknown as ProProfile;

  function open(answers: Answer[]) {
    const s = server('POST /api/pro/appointments', answers, (u) =>
      u.startsWith('/api/pro/clients') ? { status: 200, body: { items: [] } } : undefined,
    );
    const onCreated = vi.fn();
    render(
      <ManualBookingDialog
        providerId="p1"
        profile={PROFILE}
        dateTimeIso="2027-01-15T14:30:00.000Z"
        onClose={() => {}}
        onCreated={onCreated}
      />,
    );
    fireEvent.click(screen.getByRole('checkbox', { name: /Tresses/ }));
    fireEvent.click(screen.getByRole('checkbox', { name: 'Client sans numéro' }));
    const create = () => fireEvent.click(screen.getByRole('button', { name: 'Créer' }));
    return { ...s, create, onCreated };
  }

  it('lost once: asked again with the same key, and it is created', async () => {
    const { keys, create, onCreated } = open(['throw', { status: 201, body: { id: 'm1' } }]);
    create();
    await waitFor(() => expect(onCreated).toHaveBeenCalled());
    expect(keys).toHaveLength(2);
    expect(keys[1]).toBe(keys[0]);
  });

  it('lost twice: « Réessayer » sends the SAME key; a changed form a new one', async () => {
    const { keys, create } = open(['throw']);
    create();
    expect(await screen.findByText('Création impossible. Réessayez.')).toBeInTheDocument();
    create();
    await waitFor(() => expect(keys).toHaveLength(4));
    expect(new Set(keys).size).toBe(1);
    fireEvent.click(screen.getByRole('checkbox', { name: /Tresses/ })); // off
    fireEvent.click(screen.getByRole('checkbox', { name: /Tresses/ })); // on again: same form
    create();
    await waitFor(() => expect(keys).toHaveLength(6));
    expect(keys[4]).toBe(keys[0]);
  });
});

describe('« Ajouter » (a note on the client card)', () => {
  const CARD: SalonClientCard = {
    id: 'sc1',
    displayName: 'Koffi',
    phone: '+2250700000101',
    tags: [],
    lastVisitAt: null,
    linked: false,
    createdAt: '2026-10-01T09:00:00.000Z',
    stats: { visits: 3, spentFcfa: 45000, noShows: 0, cancellations: 0 },
    notes: [],
  };
  const note = (id: string) => ({
    id,
    body: 'Allergie au henné',
    authorName: 'Moi',
    createdAt: '2026-10-21T09:00:00.000Z',
  });

  async function open(answers: Answer[]) {
    const s = server(`POST /api/pro/clients/${CARD.id}/notes`, answers, (u) => {
      if (u === '/api/pro/me') {
        return {
          status: 200,
          body: { account: { id: 'acc-1' }, provider: { id: 'p1', name: 'B', status: 'active', services: [] } },
        };
      }
      if (u.startsWith(`/api/pro/clients/${CARD.id}/visits`)) return { status: 200, body: { items: [], total: 0 } };
      if (u.startsWith(`/api/pro/clients/${CARD.id}?`)) return { status: 200, body: CARD };
      return undefined;
    });
    render(<ClientCardClient clientId={CARD.id} />);
    await screen.findByRole('heading', { level: 1, name: /^Koffi/ });
    const add = (text: string) => {
      fireEvent.change(screen.getByLabelText('Ajouter une note'), { target: { value: text } });
      fireEvent.click(screen.getByRole('button', { name: 'Ajouter' }));
    };
    return { ...s, add };
  }

  it('a 2xx whose body was lost: asked again → the note shows ONCE', async () => {
    const { keys, add } = await open([{ status: 201, raw: '' }, { status: 201, body: note('n1') }]);
    add('Allergie au henné');
    expect(await screen.findByText('Allergie au henné')).toBeInTheDocument();
    expect(screen.getAllByText('Allergie au henné')).toHaveLength(1);
    expect(keys[1]).toBe(keys[0]);
  });

  it('the note never came back, even asked again: « Ajouter » once more REPLAYS it — never a second note', async () => {
    const { keys, add } = await open([
      { status: 201, raw: '' },
      { status: 201, raw: '' },
      { status: 201, body: note('n1') },
    ]);
    add('Allergie au henné');
    await waitFor(() => expect(keys).toHaveLength(2));
    expect(screen.queryByText('Allergie au henné', { selector: 'li *' })).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Ajouter' }));
    expect(await screen.findAllByText('Allergie au henné')).toHaveLength(1);
    expect(new Set(keys).size).toBe(1);
  });

  it('after a success, the same words again are a NEW note (a new key)', async () => {
    const { keys, add } = await open([{ status: 201, body: note('n1') }, { status: 201, body: note('n2') }]);
    add('Allergie au henné');
    await screen.findByText('Allergie au henné');
    add('Allergie au henné');
    await waitFor(() => expect(keys).toHaveLength(2));
    expect(keys[1]).not.toBe(keys[0]);
  });
});

describe('« Envoyer l’invitation »', () => {
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

  function open(answers: Answer[]) {
    const s = server('POST /api/pro/members', answers, () => undefined);
    const onInvited = vi.fn();
    render(
      <InviteMemberDialog
        providerId="p1"
        artists={[]}
        onArtistCreated={vi.fn()}
        onClose={vi.fn()}
        onInvited={onInvited}
      />,
    );
    fireEvent.change(screen.getByPlaceholderText('collaborateur@exemple.com'), {
      target: { value: 'awa@salon.test' },
    });
    fireEvent.click(screen.getByRole('button', { name: /^Manager/ }));
    const send = () => fireEvent.click(screen.getByRole('button', { name: 'Envoyer l’invitation' }));
    return { ...s, send, onInvited };
  }

  it('lost once: asked again with the same key — invited once, never « déjà dans l’équipe »', async () => {
    const { keys, send, onInvited } = open(['throw', { status: 201, body: member }]);
    send();
    await waitFor(() => expect(onInvited).toHaveBeenCalledTimes(1));
    expect(keys[1]).toBe(keys[0]);
    expect(screen.queryByText(/déjà dans l’équipe/)).toBeNull();
  });

  it('lost twice: the retry sends the SAME key', async () => {
    const { keys, send } = open(['throw']);
    send();
    await waitFor(() => expect(keys).toHaveLength(2));
    await screen.findByText('Une erreur est survenue. Réessayez.');
    send();
    await waitFor(() => expect(keys).toHaveLength(4));
    expect(new Set(keys).size).toBe(1);
  });
});

import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const push = vi.fn();
// Stable object: the load effects depend on [router].
const routerMock = { replace, push, refresh: vi.fn(), back: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/mon-compte',
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock('@sentry/nextjs', () => ({ captureMessage: vi.fn() }));

import { AccountClient } from '../components/account/AccountClient';
import { AppointmentDetailClient } from '../components/account/AppointmentDetailClient';
import { NotificationsClient } from '../components/account/NotificationsClient';
import { ReviewForm } from '../components/account/ReviewForm';
import { LoginOptions } from '../components/auth/LoginOptions';
import { BookingFlow } from '../components/booking/BookingFlow';
import { DepositProof } from '../components/booking/DepositProof';
import { FavoriteButton } from '../components/provider/FavoriteButton';
import { ReviewList } from '../components/provider/ReviewList';
import { resetLocalitiesClientCache } from '../lib/use-localities';
import { providerFixture } from './fixtures';

/// docs/design/web-consumer-network-failure.md §1/§3/§10 — every save path
/// under a dropped connection. Before: the write threw, `setBusy(false)` never
/// ran, and the button stayed busy for ever with no word — « Se déconnecter »
/// did nothing at all. Now: the button comes back with its failure sentence;
/// where that sentence blamed the person's input (the e-mail, the code, the
/// image), it says « Pas de connexion. Réessayez. », as the app does; and
/// « Se déconnecter » never leaves the page over a session still alive.

type Answer = 'throw' | { status: number; body?: unknown };

/// Answers by « METHOD path » first, then by path (query stripped); anything
/// unlisted is a 404.
function mockFetch(answers: Record<string, Answer>) {
  const fn = vi.fn(async (url: string, init?: RequestInit) => {
    const path = String(url).split('?')[0];
    const method = init?.method ?? 'GET';
    const a = answers[`${method} ${path}`] ?? answers[path] ?? answers['*'];
    if (a === 'throw') throw new TypeError('Failed to fetch');
    if (!a) return new Response('{}', { status: 404 });
    return new Response(JSON.stringify(a.body ?? {}), { status: a.status });
  });
  vi.stubGlobal('fetch', fn);
  return fn;
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  resetLocalitiesClientCache();
  replace.mockReset();
  push.mockReset();
});

const NO_CONNECTION = 'Pas de connexion. Réessayez.';
const GENERIC = 'Une erreur est survenue. Réessayez.';

const ME = { id: 'u1', name: 'Awa', email: 'awa@x.ci', phoneNumber: '+2250707123456' };
const APPT = {
  id: 'a1',
  status: 'confirmed',
  appointmentDate: '2099-01-15T09:00:00.000Z',
  providerId: 'p1',
  providerName: 'Beauté Divine',
  providerSlug: 'beaute-divine',
  providerStatus: 'active',
  serviceIds: ['s1'],
  durationMinutes: 30,
  totalPrice: 5000,
};
const ACCOUNT_READS: Record<string, Answer> = {
  'GET /api/me': { status: 200, body: ME },
  'GET /api/appointments': { status: 200, body: { items: [] } },
  'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
};

/// The fault is NOT on the field: nothing points at the input.
function expectFieldNotAccused(input: HTMLElement) {
  expect(input).not.toHaveAttribute('aria-invalid', 'true');
}

describe('Mon compte — « Se déconnecter » (the session is httpOnly cookies only the BFF can clear)', () => {
  it('no network: stays on the page, says so, gives the button back — never a signed-out look over a live session', async () => {
    mockFetch({ ...ACCOUNT_READS, 'POST /api/auth/logout': 'throw' });
    render(<AccountClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Se déconnecter' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(NO_CONNECTION);
    expect(screen.getByRole('button', { name: 'Se déconnecter' })).toBeEnabled();
    expect(replace).not.toHaveBeenCalled();
  });

  it('the BFF refused (500): stays, the generic sentence', async () => {
    mockFetch({ ...ACCOUNT_READS, 'POST /api/auth/logout': { status: 500 } });
    render(<AccountClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Se déconnecter' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(GENERIC);
    expect(replace).not.toHaveBeenCalled();
  });

  it('the BFF answered OK: home', async () => {
    mockFetch({ ...ACCOUNT_READS, 'POST /api/auth/logout': { status: 200, body: { ok: true } } });
    render(<AccountClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Se déconnecter' }));
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/'));
  });
});

describe('Mon compte — the other saves', () => {
  it('the contact phone: « L’enregistrement a échoué. Réessayez. », the button comes back', async () => {
    mockFetch({ ...ACCOUNT_READS, 'PATCH /api/me': 'throw' });
    render(<AccountClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Modifier' }));
    const field = screen.getByLabelText('Numéro de téléphone');
    fireEvent.change(field, { target: { value: '+225 07 07 12 34 99' } });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('L’enregistrement a échoué. Réessayez.');
    expect(screen.getByRole('button', { name: 'Enregistrer' })).toBeEnabled();
    expectFieldNotAccused(field);
  });

  it('the name: « OK » comes back', async () => {
    const f = mockFetch({ ...ACCOUNT_READS, 'PATCH /api/me': 'throw' });
    render(<AccountClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Modifier le nom' }));
    fireEvent.change(screen.getByRole('textbox', { name: 'Nom' }), { target: { value: 'Awa K.' } });
    fireEvent.click(screen.getByRole('button', { name: 'OK' }));

    await waitFor(() =>
      expect(f.mock.calls.some(([, init]) => (init as RequestInit | undefined)?.method === 'PATCH')).toBe(true),
    );
    await waitFor(() => expect(screen.getByRole('button', { name: 'OK' })).toBeEnabled());
  });

  it('the deletion: « La suppression a échoué. Réessayez. », and the page stays', async () => {
    mockFetch({ ...ACCOUNT_READS, 'DELETE /api/me': 'throw' });
    render(<AccountClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Supprimer mon compte' }));
    fireEvent.change(screen.getByRole('textbox', { name: 'Confirmation de suppression' }), {
      target: { value: 'SUPPRIMER' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Supprimer définitivement' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('La suppression a échoué. Réessayez.');
    expect(screen.getByRole('button', { name: 'Supprimer définitivement' })).toBeEnabled();
    expect(replace).not.toHaveBeenCalled();
  });
});

describe('Le détail d’un rendez-vous — annuler, reporter', () => {
  const READS: Record<string, Answer> = {
    'GET /api/appointments/a1': { status: 200, body: APPT },
    'GET /api/localities': { status: 200, body: { countries: [] } },
    'GET /api/availability': { status: 200, body: { slots: ['2099-01-16T10:00:00.000Z'] } },
  };

  it('« Confirmer l’annulation » without network: « L’annulation a échoué. Réessayez. »', async () => {
    mockFetch({ ...READS, 'POST /api/appointments/a1/cancel': 'throw' });
    render(<AppointmentDetailClient id="a1" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Annuler le rendez-vous' }));
    fireEvent.click(screen.getByRole('button', { name: 'Confirmer l’annulation' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('L’annulation a échoué. Réessayez.');
    // The booking is still on screen, not an error page.
    expect(screen.getByRole('heading', { level: 1, name: 'Beauté Divine' })).toBeInTheDocument();
  });

  it('« Confirmer le report » without network: « Le report a échoué. Réessayez. », the button comes back', async () => {
    mockFetch({ ...READS, 'POST /api/appointments/a1/reschedule': 'throw' });
    render(<AppointmentDetailClient id="a1" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Reporter' }));
    fireEvent.click(await screen.findByRole('button', { name: /^\d{2}:\d{2}$/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Confirmer le report' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('Le report a échoué. Réessayez.');
    expect(screen.getByRole('button', { name: 'Confirmer le report' })).toBeEnabled();
  });
});

describe('L’avis — the review, its photo, its report', () => {
  const file = new File(['x'], 'photo.jpg', { type: 'image/jpeg' });

  it('« Envoyer l’avis » without network: « L’envoi a échoué. Réessayez. », the button comes back', async () => {
    mockFetch({ '*': 'throw' });
    render(<ReviewForm appointmentId="a1" />);
    fireEvent.click(screen.getByRole('radio', { name: '5 étoiles' }));
    fireEvent.click(screen.getByRole('button', { name: 'Envoyer l’avis' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('L’envoi a échoué. Réessayez.');
    expect(screen.getByRole('button', { name: 'Envoyer l’avis' })).toBeEnabled();
  });

  it('« Ajouter une photo » without network: the photo sentence, and the button stops spinning', async () => {
    mockFetch({ '*': 'throw' });
    render(<ReviewForm appointmentId="a1" />);
    fireEvent.change(screen.getByLabelText('Photo de l’avis'), { target: { files: [file] } });

    expect(await screen.findByRole('alert')).toHaveTextContent('Échec de l’envoi de la photo. Réessayez.');
    expect(screen.getByRole('button', { name: 'Ajouter une photo' })).toBeEnabled();
    expect(screen.getByRole('button', { name: 'Envoyer l’avis' })).toBeEnabled();
  });

  it('« Signaler » without network: « Le signalement a échoué. Réessayez. », the button comes back', async () => {
    mockFetch({ '*': 'throw' });
    render(
      <ReviewList
        reviews={[{ id: 'r1', userName: 'Awa', rating: 5, text: 'Top', createdAt: '2026-10-01T10:00:00.000Z' } as never]}
        rating={5}
        reviewCount={1}
        slug="beaute-divine"
      />,
    );
    fireEvent.click(screen.getByRole('button', { name: 'Signaler' }));
    const send = screen.getAllByRole('button', { name: 'Signaler' }).at(-1)!;
    fireEvent.click(send);

    expect(await screen.findByRole('alert')).toHaveTextContent('Le signalement a échoué. Réessayez.');
    expect(screen.getAllByRole('button', { name: 'Signaler' }).at(-1)).toBeEnabled();
  });
});

describe('Notifications — a preference', () => {
  it('without network: the switch goes back, « Impossible d’enregistrer. Réessayez. »', async () => {
    mockFetch({
      'GET /api/me/notifications': { status: 200, body: { items: [] } },
      'GET /api/me/notification-preferences': {
        status: 200,
        body: { reminders: true, marketing: true, push: true },
      },
      'PUT /api/me/notification-preferences': 'throw',
    });
    render(<NotificationsClient />);
    const toggle = await screen.findByRole('switch', { name: 'Offres & promotions' });
    expect(toggle).toHaveAttribute('aria-checked', 'true');
    fireEvent.click(toggle);

    expect(await screen.findByRole('alert')).toHaveTextContent('Impossible d’enregistrer. Réessayez.');
    expect(toggle).toHaveAttribute('aria-checked', 'true');
  });
});

describe('Connexion — e-mail', () => {
  it('« Continuer avec e-mail » without network: « Pas de connexion. Réessayez. » — the e-mail is not accused', async () => {
    mockFetch({ '*': 'throw' });
    render(<LoginOptions onSuccess={vi.fn()} />);
    const email = screen.getByLabelText('Votre e-mail');
    fireEvent.change(email, { target: { value: 'awa@x.ci' } });
    fireEvent.click(screen.getByRole('button', { name: 'Continuer avec e-mail' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(NO_CONNECTION);
    expect(screen.queryByText('E-mail invalide ou envoi impossible.')).toBeNull();
    expectFieldNotAccused(email);
    expect(screen.getByRole('button', { name: 'Continuer avec e-mail' })).toBeEnabled();
  });

  it('« Se connecter » without network: « Pas de connexion. Réessayez. » — never « Code incorrect ou expiré. » under the field', async () => {
    mockFetch({
      'POST /api/auth/email/request': { status: 202, body: { expiresInSeconds: 300 } },
      'POST /api/auth/email/verify': 'throw',
    });
    render(<LoginOptions onSuccess={vi.fn()} />);
    fireEvent.change(screen.getByLabelText('Votre e-mail'), { target: { value: 'awa@x.ci' } });
    fireEvent.click(screen.getByRole('button', { name: 'Continuer avec e-mail' }));
    const code = await screen.findByLabelText('Code à 6 chiffres');
    fireEvent.change(code, { target: { value: '123456' } });
    fireEvent.click(screen.getByRole('button', { name: 'Se connecter' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(NO_CONNECTION);
    expect(screen.queryByText('Code incorrect ou expiré.')).toBeNull();
    expectFieldNotAccused(code);
    expect(screen.getByRole('button', { name: 'Se connecter' })).toBeEnabled();
  });

  it('a wrong code is still the field’s fault (unchanged)', async () => {
    mockFetch({
      'POST /api/auth/email/request': { status: 202, body: { expiresInSeconds: 300 } },
      'POST /api/auth/email/verify': { status: 400, body: { error: 'otp_invalid' } },
    });
    render(<LoginOptions onSuccess={vi.fn()} />);
    fireEvent.change(screen.getByLabelText('Votre e-mail'), { target: { value: 'awa@x.ci' } });
    fireEvent.click(screen.getByRole('button', { name: 'Continuer avec e-mail' }));
    const code = await screen.findByLabelText('Code à 6 chiffres');
    fireEvent.change(code, { target: { value: '000000' } });
    fireEvent.click(screen.getByRole('button', { name: 'Se connecter' }));

    expect(await screen.findByText('Code incorrect ou expiré.')).toBeInTheDocument();
    expect(code).toHaveAttribute('aria-invalid', 'true');
  });
});

describe('Réserver — « Confirmer la réservation »', () => {
  const SLOT = '2099-01-15T14:30:00.000Z';

  async function openConfirm(answers: Record<string, Answer>) {
    mockFetch({
      'GET /api/availability': { status: 200, body: { slots: [SLOT] } },
      'GET /api/me': { status: 200, body: ME },
      ...answers,
    });
    render(<BookingFlow provider={providerFixture} prefillServiceIds={['s1']} />);
    fireEvent.click(await screen.findByRole('button', { name: /^\d{2}:\d{2}$/ }));
    fireEvent.click(screen.getAllByRole('button', { name: 'Confirmer' })[0]);
    const field = await screen.findByLabelText('Numéro de téléphone');
    return { field, submit: screen.getByRole('button', { name: 'Confirmer la réservation' }) };
  }

  // docs/design/write-idempotency.md §8 (owner Q4): it said « La réservation
  // a échoué. Réessayez. » — and a retry could book twice. Asked again once
  // with the same key, then the truth: nothing answered, and « Réessayer » is
  // safe (it sends that key again).
  it('the booking without network: asked again once, then « Pas de connexion. Réessayez. », the button comes back', async () => {
    const { submit } = await openConfirm({ 'POST /api/bookings': 'throw' });
    const f = vi.mocked(fetch);
    fireEvent.click(submit);

    expect(await screen.findByRole('alert')).toHaveTextContent(NO_CONNECTION);
    expect(f.mock.calls.filter(([u, i]) => u === '/api/bookings' && i?.method === 'POST')).toHaveLength(2);
    expect(submit).toBeEnabled();
  });

  it('a changed number without network: « Votre numéro n’a pas pu être enregistré. Réessayez. » — the number is not accused', async () => {
    const { field, submit } = await openConfirm({ 'PATCH /api/me': 'throw' });
    fireEvent.change(field, { target: { value: '+225 07 07 12 34 99' } });
    fireEvent.click(submit);

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Votre numéro n’a pas pu être enregistré. Réessayez.',
    );
    expectFieldNotAccused(field);
    expect(submit).toBeEnabled();
  });
});

describe('L’acompte — « Envoyer la preuve »', () => {
  const file = new File(['x'], 'capture.jpg', { type: 'image/jpeg' });

  async function sendProof(answers: Record<string, Answer>) {
    mockFetch({ 'GET /api/localities': { status: 200, body: { countries: [] } }, ...answers });
    render(<DepositProof appointmentId="a1" amount={5000} number="0707123456" />);
    fireEvent.change(screen.getByLabelText('Capture du paiement'), { target: { files: [file] } });
    fireEvent.click(screen.getByRole('button', { name: 'Envoyer la preuve' }));
  }

  it('the presign without network: « Pas de connexion. Réessayez. » — never « Vérifiez l’image »', async () => {
    await sendProof({ 'POST /api/uploads/sign': 'throw' });
    expect(await screen.findByRole('alert')).toHaveTextContent(NO_CONNECTION);
    expect(screen.queryByText(/Vérifiez l’image/)).toBeNull();
    expect(screen.getByRole('button', { name: 'Envoyer la preuve' })).toBeEnabled();
  });

  it('the attach without network: « Pas de connexion. Réessayez. »', async () => {
    await sendProof({
      'POST /api/uploads/sign': {
        status: 200,
        body: { method: 'PUT', uploadUrl: 'https://r2.test/up', headers: {}, key: 'deposit/u1/1.jpg' },
      },
      'PUT https://r2.test/up': { status: 200 },
      'POST /api/appointments/a1/deposit': 'throw',
    });
    expect(await screen.findByRole('alert')).toHaveTextContent(NO_CONNECTION);
    expect(screen.queryByText(/Vérifiez l’image/)).toBeNull();
  });

  it('a refused file is still « Vérifiez l’image » (unchanged)', async () => {
    await sendProof({ 'POST /api/uploads/sign': { status: 400, body: { error: 'invalid_content_type' } } });
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'L’envoi a échoué. Vérifiez l’image et réessayez.',
    );
  });
});

describe('Le ♥ du salon', () => {
  it('without network: the button comes back, unchanged', async () => {
    const f = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': 'throw',
    });
    render(<FavoriteButton providerId="p1" slug="beaute-divine" />);
    await waitFor(() => expect(f).toHaveBeenCalledTimes(1));
    fireEvent.click(screen.getByRole('button', { name: /Ajouter aux favoris/ }));

    await waitFor(() => expect(f).toHaveBeenCalledTimes(2));
    await waitFor(() =>
      expect(screen.getByRole('button', { name: /Ajouter aux favoris/ })).toBeEnabled(),
    );
    expect(push).not.toHaveBeenCalled();
  });
});

import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { JournalPanel } from '../components/pro/JournalPanel';
import { NO_CONNECTION_MESSAGE } from '../lib/api/network';
import { formatFcfa } from '../lib/format';
import type { Membership } from '../lib/pro/team';
import type { ProAppointment } from '../lib/pro/today';

/// docs/design/web-pro-journal-panel-deposit.md — the « Journée » panel.
///
/// The defect (audit 2026-10-19 §3 n° 1, P1): the panel offered « Accepter » on
/// a deposit-required request without the amount, the screenshot, or a way to
/// the booking's page — a salon could accept without seeing whether the
/// deposit was sent. The app opens the booking with its screenshot
/// (`pro_journal_screen.dart:290` → `pro_appointment_detail_screen.dart:229-260`).
/// And « Non présenté » was offered on any confirmed booking, future ones
/// included, with no confirmation — the app waits for the start and asks.

const PROOF_URL = 'https://acct.r2.cloudflarestorage.com/deposit/u2/proof.jpg?X-Amz-Signature=s';
const HOUR = 3_600_000;
const inHours = (h: number) => new Date(Date.now() + h * HOUR).toISOString();

const GUIDANCE =
  'Confirmez le rendez-vous une fois l’acompte reçu sur votre compte Mobile Money.';
const NO_PROOF = 'Aucune capture jointe pour le moment.';
const UNAVAILABLE = 'Capture indisponible. Réessayez.';
const ENLARGE = 'Agrandir le justificatif d’acompte';

const PENDING_WITH_PROOF: ProAppointment = {
  id: 'pj2',
  status: 'pending',
  appointmentDate: inHours(30),
  clientDisplayName: 'Aminata',
  serviceIds: ['s1'],
  totalPrice: 15000,
  depositAmount: 5000,
  depositScreenshotUrl: 'deposit/u2/proof.jpg',
};

const STAFF: Membership = {
  role: 'staff',
  capabilities: ['journal.manage.own', 'journal.view.own'],
  artistId: 'artist-a',
  artistName: 'Awa',
};

type Answer = 'throw' | { status: number; body?: unknown };

/// Every GET of the screenshot URL, and every lifecycle POST.
const proofReads: string[] = [];
const posts: string[] = [];
let proofAnswers: Answer[] = [];

function mockFetch(proof: Answer[] = [{ status: 200, body: { url: PROOF_URL } }]) {
  proofReads.length = 0;
  posts.length = 0;
  proofAnswers = [...proof];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      if (u.endsWith('/deposit-screenshot')) {
        proofReads.push(u);
        // Running out repeats the last answer.
        const a = proofAnswers.length > 1 ? proofAnswers.shift()! : proofAnswers[0];
        if (a === 'throw') throw new TypeError('Failed to fetch');
        return new Response(JSON.stringify(a.body ?? {}), { status: a.status });
      }
      if (init?.method === 'POST') {
        posts.push(u);
        return new Response('{}', { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

function renderPanel(
  appt: ProAppointment,
  opts: { membership?: Membership | null; onChanged?: () => void } = {},
) {
  return render(
    <JournalPanel
      providerId="p1"
      appt={appt}
      membership={opts.membership ?? null}
      serviceName={() => 'Tresses'}
      onClose={() => {}}
      onChanged={opts.onChanged ?? (() => {})}
      onToast={() => {}}
      tz="Africa/Abidjan"
      currency="XOF"
    />,
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('the deposit in the « Journée » panel', () => {
  it('shows the announced deposit as a fact, beside the total', async () => {
    mockFetch();
    renderPanel(PENDING_WITH_PROOF);
    const panel = screen.getByRole('dialog', { name: 'Détails du rendez-vous' });
    const term = within(panel).getByText('Acompte annoncé');
    expect(term.tagName).toBe('DT');
    expect(term.nextElementSibling).toHaveTextContent(formatFcfa(5000, 'XOF'));
    await screen.findByRole('button', { name: ENLARGE });
  });

  it('pending: the app’s guidance, then the screenshot — loaded without a click', async () => {
    mockFetch();
    renderPanel(PENDING_WITH_PROOF);
    expect(screen.getByText(GUIDANCE)).toBeInTheDocument();
    const thumb = await screen.findByRole('button', { name: ENLARGE });
    expect(within(thumb).getByAltText('Justificatif d’acompte')).toHaveAttribute(
      'src',
      PROOF_URL,
    );
    expect(proofReads).toEqual(['/api/pro/appointments/pj2/deposit-screenshot']);
  });

  it('the thumbnail opens the enlarged screenshot (the app’s tap-to-view)', async () => {
    mockFetch();
    renderPanel(PENDING_WITH_PROOF);
    fireEvent.click(await screen.findByRole('button', { name: ENLARGE }));
    const box = screen.getByRole('dialog', { name: 'Justificatif d’acompte' });
    expect(within(box).getByAltText('Justificatif d’acompte')).toHaveAttribute(
      'src',
      PROOF_URL,
    );
  });

  it('confirmed: no guidance (Q1 — it asks for what is already done), the screenshot stays', async () => {
    mockFetch();
    renderPanel({ ...PENDING_WITH_PROOF, status: 'confirmed' });
    await screen.findByRole('button', { name: ENLARGE });
    expect(screen.queryByText(GUIDANCE)).toBeNull();
  });

  it('a deposit without a screenshot says so — and asks nothing of the server', async () => {
    mockFetch();
    renderPanel({ ...PENDING_WITH_PROOF, depositScreenshotUrl: null });
    expect(screen.getByText(NO_PROOF)).toBeInTheDocument();
    expect(screen.getByText(GUIDANCE)).toBeInTheDocument();
    await new Promise((r) => setTimeout(r, 0));
    expect(proofReads).toEqual([]);
  });

  it('no deposit: no line, no guidance, no screenshot', async () => {
    mockFetch();
    renderPanel({ ...PENDING_WITH_PROOF, depositAmount: 0, depositScreenshotUrl: null });
    expect(screen.queryByText('Acompte annoncé')).toBeNull();
    expect(screen.queryByText(GUIDANCE)).toBeNull();
    expect(screen.queryByText(NO_PROOF)).toBeNull();
    await new Promise((r) => setTimeout(r, 0));
    expect(proofReads).toEqual([]);
  });

  it('no answer says « Pas de connexion », and « Réessayer » asks again', async () => {
    mockFetch(['throw', { status: 200, body: { url: PROOF_URL } }]);
    renderPanel(PENDING_WITH_PROOF);
    expect(await screen.findByText(NO_CONNECTION_MESSAGE)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    await screen.findByRole('button', { name: ENLARGE });
    expect(proofReads).toHaveLength(2);
    expect(screen.queryByText(NO_CONNECTION_MESSAGE)).toBeNull();
  });

  it('a refusal is not silent: « Capture indisponible. Réessayez. »', async () => {
    for (const status of [404, 500]) {
      mockFetch([{ status, body: { error: 'x' } }]);
      renderPanel(PENDING_WITH_PROOF);
      expect(await screen.findByText(UNAVAILABLE)).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
      cleanup();
    }
  });

  it('an image that will not load (the 5-minute URL expired) says so, and « Réessayer » signs a NEW one', async () => {
    mockFetch();
    renderPanel(PENDING_WITH_PROOF);
    const thumb = await screen.findByRole('button', { name: ENLARGE });
    fireEvent.error(within(thumb).getByAltText('Justificatif d’acompte'));
    expect(await screen.findByText(UNAVAILABLE)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    await screen.findByRole('button', { name: ENLARGE });
    expect(proofReads).toHaveLength(2);
  });

  it('the failure sentence lands in a live region that was there before it', async () => {
    mockFetch(['throw']);
    renderPanel(PENDING_WITH_PROOF);
    const region = document.querySelector('[data-deposit-proof][aria-live="polite"]');
    expect(region, 'the polite region must exist from the first render').not.toBeNull();
    expect(region).not.toHaveTextContent(NO_CONNECTION_MESSAGE);
    await screen.findByText(NO_CONNECTION_MESSAGE);
    expect(region).toHaveTextContent(NO_CONNECTION_MESSAGE);
  });

  it('a Collaborateur sees the amount only — the server would refuse the screenshot', async () => {
    // deposit_service.dart: a provider needs journal.view.all; staff has
    // journal.view.own. The app asks anyway and says « Capture indisponible ».
    mockFetch();
    renderPanel(
      { ...PENDING_WITH_PROOF, status: 'confirmed' },
      { membership: STAFF },
    );
    expect(screen.getByText('Acompte annoncé')).toBeInTheDocument();
    expect(screen.queryByText(GUIDANCE)).toBeNull();
    expect(screen.queryByText(NO_PROOF)).toBeNull();
    expect(screen.queryByRole('button', { name: ENLARGE })).toBeNull();
    await new Promise((r) => setTimeout(r, 0));
    expect(proofReads).toEqual([]);
  });
});

describe('« Voir le rendez-vous »', () => {
  it('links the panel to the booking’s own page', async () => {
    mockFetch();
    renderPanel(PENDING_WITH_PROOF);
    expect(screen.getByRole('link', { name: 'Voir le rendez-vous' })).toHaveAttribute(
      'href',
      '/pro/rendez-vous/pj2',
    );
    await screen.findByRole('button', { name: ENLARGE });
  });

  it('for a Collaborateur too (their own booking opens)', () => {
    mockFetch();
    renderPanel({ ...PENDING_WITH_PROOF, status: 'confirmed' }, { membership: STAFF });
    expect(screen.getByRole('link', { name: 'Voir le rendez-vous' })).toHaveAttribute(
      'href',
      '/pro/rendez-vous/pj2',
    );
  });
});

describe('« Non présenté » in the panel', () => {
  const CONFIRMED_NO_DEPOSIT: ProAppointment = {
    ...PENDING_WITH_PROOF,
    status: 'confirmed',
    depositAmount: 0,
    depositScreenshotUrl: null,
  };

  it('is not offered before the booking starts', () => {
    mockFetch();
    renderPanel({ ...CONFIRMED_NO_DEPOSIT, appointmentDate: inHours(2) });
    expect(screen.getByRole('button', { name: 'Terminé' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Non présenté' })).toBeNull();
  });

  it('once started, it asks first — and nothing is sent until « Marquer absent »', async () => {
    mockFetch();
    const onChanged = vi.fn();
    renderPanel({ ...CONFIRMED_NO_DEPOSIT, appointmentDate: inHours(-1) }, { onChanged });
    fireEvent.click(screen.getByRole('button', { name: 'Non présenté' }));

    expect(screen.getByText('Client absent ?')).toBeInTheDocument();
    expect(screen.getByText('Le client ne s’est pas présenté.')).toBeInTheDocument();
    // No deposit → no deposit sentence.
    expect(screen.queryByText(/L’acompte est conservé/)).toBeNull();
    expect(posts).toEqual([]);

    fireEvent.click(screen.getByRole('button', { name: 'Marquer absent' }));
    await waitFor(() => expect(posts).toEqual(['/api/pro/appointments/pj2/no-show']));
    await waitFor(() => expect(onChanged).toHaveBeenCalled());
  });

  it('« Annuler » backs out without a call', () => {
    mockFetch();
    renderPanel({ ...CONFIRMED_NO_DEPOSIT, appointmentDate: inHours(-1) });
    fireEvent.click(screen.getByRole('button', { name: 'Non présenté' }));
    fireEvent.click(screen.getByRole('button', { name: 'Annuler' }));
    expect(screen.queryByText('Client absent ?')).toBeNull();
    expect(screen.getByRole('button', { name: 'Non présenté' })).toBeInTheDocument();
    expect(posts).toEqual([]);
  });

  it('with a deposit, the confirmation says the salon keeps it', async () => {
    mockFetch();
    renderPanel({ ...PENDING_WITH_PROOF, status: 'confirmed', appointmentDate: inHours(-1) });
    fireEvent.click(screen.getByRole('button', { name: 'Non présenté' }));
    expect(
      screen.getByText('L’acompte est conservé selon votre politique d’annulation.'),
    ).toBeInTheDocument();
    await screen.findByRole('button', { name: ENLARGE });
  });
});

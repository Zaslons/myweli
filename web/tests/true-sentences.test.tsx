import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn(), back: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/',
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock('@sentry/nextjs', () => ({ captureMessage: vi.fn() }));

import ProConnexionPage from '../app/pro/connexion/page';
import { AppointmentDetailClient } from '../components/account/AppointmentDetailClient';
import { BookingFlow } from '../components/booking/BookingFlow';
import { cancellationNotice, type Appointment } from '../lib/account/appointments';
import * as appStore from '../lib/appStore';
import { formatFcfa } from '../lib/format';
import { PRO_LANDING } from '../lib/pro/landing';
import { providerFixture } from './fixtures';

/// docs/design/web-true-sentences.md — four things the site said that were not
/// true (web-flow-audit-2026-11.md P1, C1, C2, P2). Each one reads a fact the
/// page already has, so each test names the fact and the sentence it must give.

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

type Answers = Record<string, { status: number; body?: unknown }>;

/// Answers by `METHOD /path`; anything unlisted is a 404.
function serve(answers: Answers) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const key = `${init?.method ?? 'GET'} ${String(url).split('?')[0]}`;
      const a = answers[key];
      return new Response(JSON.stringify(a?.body ?? {}), { status: a?.status ?? 404 });
    }),
  );
}

describe('B12.2 cancellationNotice: what a client is told about a deposit', () => {
  const HOUR = 3_600_000;
  const AT = Date.parse('2026-12-10T10:00:00.000Z');
  const now = (hoursBefore: number, extraMs = 0) => new Date(AT - hoursBefore * HOUR + extraMs);
  const appt = (over: Partial<Appointment> = {}): Appointment =>
    ({
      id: 'a1',
      status: 'confirmed',
      appointmentDate: new Date(AT).toISOString(),
      providerId: 'p1',
      depositAmount: 5000,
      depositScreenshotUrl: 'deposit/u1/proof.jpg',
      cancellationWindowHours: 24,
      ...over,
    }) as Appointment;
  const amount = formatFcfa(5000);
  const REFUND = `D’après la règle du salon, votre acompte de ${amount} vous revient, car vous annulez plus de 24 h avant. Voyez avec le salon pour le récupérer : MyWeli ne détient aucun acompte.`;
  const KEPT = `D’après la règle du salon, votre acompte de ${amount} ne sera pas remboursé, car vous annulez moins de 24 h avant.`;
  const PAST = `D’après la règle du salon, votre acompte de ${amount} ne sera pas remboursé, car l’heure du rendez-vous est passée.`;

  it('no deposit: nothing to say', () => {
    expect(cancellationNotice(appt({ depositAmount: 0 }), now(48))).toBeNull();
    expect(cancellationNotice(appt({ depositAmount: undefined }), now(48))).toBeNull();
  });

  it('a booking the salon entered: there was no proof to ask for', () => {
    expect(
      cancellationNotice(appt({ salonEntered: true, depositScreenshotUrl: null }), now(48)),
    ).toBeNull();
  });

  it('no proof sent: says so, and promises nothing about money', () => {
    const said = cancellationNotice(appt({ depositScreenshotUrl: null }), now(1));
    expect(said).toBe('Vous n’avez envoyé aucun justificatif d’acompte pour ce rendez-vous.');
  });

  it('a minute before the cut-off: the deposit comes back, and it says who to see', () => {
    expect(cancellationNotice(appt(), now(24, -60_000))).toBe(REFUND);
  });

  it('exactly at the cut-off counts as late, as in the app', () => {
    expect(cancellationNotice(appt(), now(24))).toBe(KEPT);
  });

  it('a minute after the cut-off: not refunded', () => {
    expect(cancellationNotice(appt(), now(24, 60_000))).toBe(KEPT);
  });

  it('after the appointment’s time: « moins de 24 h avant » would be false', () => {
    expect(cancellationNotice(appt(), now(-1))).toBe(PAST);
  });

  it('a salon with no delay (0 h): no « plus de 0 h », before or after', () => {
    const none = appt({ cancellationWindowHours: 0 });
    expect(cancellationNotice(none, now(1))).toBe(
      `D’après la règle du salon, votre acompte de ${amount} vous revient, car vous annulez avant l’heure du rendez-vous. Voyez avec le salon pour le récupérer : MyWeli ne détient aucun acompte.`,
    );
    expect(cancellationNotice(none, now(-1))).toBe(PAST);
  });

  it('the delay missing from older data: no rule is invented', () => {
    expect(cancellationNotice(appt({ cancellationWindowHours: undefined }), now(48))).toBe(
      'Le remboursement de votre acompte dépend de la règle du salon. Voyez directement avec lui : MyWeli ne détient aucun acompte.',
    );
  });

  it('the amount is in the salon’s currency', () => {
    const said = cancellationNotice(appt(), now(48), 'GNF');
    expect(said).toContain(formatFcfa(5000, 'GNF'));
  });
});

describe('B12.2 on the page', () => {
  it('a late cancel with a proof sent reads the rule, not « peut ne pas »', async () => {
    serve({
      'GET /api/appointments/a1': {
        status: 200,
        body: {
          id: 'a1',
          status: 'confirmed',
          appointmentDate: new Date(Date.now() + 3_600_000).toISOString(),
          providerId: 'p1',
          providerName: 'Beauté Divine',
          depositAmount: 5000,
          depositScreenshotUrl: 'deposit/u1/proof.jpg',
          cancellationWindowHours: 24,
        },
      },
      'GET /api/localities': { status: 200, body: { countries: [] } },
    });
    render(<AppointmentDetailClient id="a1" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Annuler le rendez-vous' }));
    expect(screen.getByText(/ne sera pas remboursé, car vous annulez moins de 24/)).toBeInTheDocument();
    expect(screen.queryByText(/peut ne pas être remboursé/)).toBeNull();
  });
});

describe('B12.3 after booking: a way to the booking, and a sentence that holds', () => {
  const SLOT = '2099-01-15T14:30:00.000Z';
  const ME = { id: 'u1', name: 'Awa', email: 'awa@x.ci', phoneNumber: '+2250707123456' };

  async function book(appointment: Record<string, unknown>) {
    serve({
      'GET /api/availability': { status: 200, body: { slots: [SLOT] } },
      'GET /api/me': { status: 200, body: ME },
      'GET /api/localities': { status: 200, body: { countries: [] } },
      'POST /api/bookings': { status: 201, body: { ok: true, appointment } },
    });
    render(<BookingFlow provider={providerFixture} prefillServiceIds={['s1']} />);
    fireEvent.click(await screen.findByRole('button', { name: /^\d{2}:\d{2}$/ }));
    fireEvent.click(screen.getAllByRole('button', { name: 'Confirmer' })[0]);
    await screen.findByLabelText('Numéro de téléphone');
    fireEvent.click(screen.getByRole('button', { name: 'Confirmer la réservation' }));
    await screen.findByText('Réservation envoyée ✓');
  }

  it('no deposit: the link to the booking is the page’s main action', async () => {
    await book({ id: 'a1', status: 'pending', depositAmount: 0 });
    const link = screen.getByRole('link', { name: 'Voir mon rendez-vous' });
    expect(link).toHaveAttribute('href', '/mon-compte/a1');
    expect(link).toHaveClass('bg-primary');
    expect(
      screen.getByText(
        'Beauté Divine va confirmer votre rendez-vous. Sa réponse apparaîtra dans vos rendez-vous et vos notifications.',
      ),
    ).toBeInTheDocument();
    expect(screen.queryByText(/Vous recevrez une/)).toBeNull();
  });

  it('a deposit: sending the proof stays the main action', async () => {
    await book({ id: 'a1', status: 'pending', depositAmount: 5000 });
    expect(screen.getByLabelText('Capture du paiement')).toBeInTheDocument();
    const link = screen.getByRole('link', { name: 'Voir mon rendez-vous' });
    expect(link).toHaveAttribute('href', '/mon-compte/a1');
    expect(link).not.toHaveClass('bg-primary');
  });

  it('no id in the answer: still somewhere to go, never a dead end', async () => {
    await book({ status: 'pending', depositAmount: 0 });
    expect(screen.getByRole('link', { name: 'Voir mes rendez-vous' })).toHaveAttribute(
      'href',
      '/mon-compte',
    );
  });
});

describe('B12.4 /pro/connexion never sends a new salon round in a circle', () => {
  beforeEach(() => {
    serve({ 'GET /api/pro/me': { status: 401, body: { error: 'unauthorized' } } });
  });

  // `served-html.spec.ts` cannot see this: its build has no store URLs, and the
  // block only ever appeared once they were set. So this sets one.
  it('with store URLs set: no « dans l’app », no store link, and the way to sign up', async () => {
    vi.spyOn(appStore, 'appStoreUrl').mockReturnValue('https://apps.apple.com/app/x');
    const { container } = render(<ProConnexionPage />);
    const signUp = await screen.findAllByRole('link', { name: 'Créer mon compte' });
    expect(signUp[0]).toHaveAttribute('href', '/pro/inscription');
    expect(container).not.toHaveTextContent(/dans l[’']app/);
    expect(container.querySelector('a[href*="apps.apple.com"]')).toBeNull();
  });
});

describe('B12.1 the trial’s start, said one way', () => {
  it('step 3 of /professionnels does not say the trial starts there', () => {
    // B0.18 (salon-go-live-approval.md §6.4, Q9): the salon ASKS; MyWeli
    // validates first. Owner-approved word for word (a no-break space before
    // the colon, as the site writes French).
    expect(PRO_LANDING.steps[2]).toBe(
      'Demandez la mise en ligne : une fois votre salon validé, vos clients peuvent réserver',
    );
  });

  // The clock starts at the first choice, or at go-live with no choice
  // (salon_subscription_service.dart), so neither claim can stand anywhere on
  // the site. Strings and comments alike: a comment repeating it misled once.
  it('no source still says the trial starts at go-live', () => {
    const WEB = join(__dirname, '..');
    const walk = (dir: string): string[] =>
      readdirSync(dir).flatMap((name) => {
        const p = join(dir, name);
        return statSync(p).isDirectory() ? walk(p) : /\.tsx?$/.test(name) ? [p] : [];
      });
    const stale = ['app', 'components', 'lib']
      .flatMap((d) => walk(join(WEB, d)))
      .filter((f) => !f.endsWith('schema.ts'))
      .filter((f) => /démarre à la mise en ligne|vos 3 mois offerts commencent/i.test(readFileSync(f, 'utf8')));
    expect(stale).toEqual([]);
  });
});

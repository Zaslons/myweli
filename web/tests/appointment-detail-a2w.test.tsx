import { cleanup, render, screen, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn(), back: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/mon-compte/a1',
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock('@sentry/nextjs', () => ({ captureMessage: vi.fn() }));
vi.mock('next/dynamic', () => ({ default: () => () => null }));

import { AppointmentDetailClient } from '../components/account/AppointmentDetailClient';
import { type Appointment, DEPOSIT_SEE_THE_SALON } from '../lib/account/appointments';

/// docs/design/appointment-detail-complete.md §2.2–§2.8 (A2w, decisions
/// 194–203): the website's detail, section by section, as the app's.

const NOW = new Date('2026-11-23T12:00:00.000Z');
const DAY = 86_400_000;
const at = (ms: number) => new Date(Date.parse('2026-11-23T09:00:00.000Z') + ms).toISOString();

const base: Appointment = {
  id: 'a1',
  status: 'confirmed',
  appointmentDate: at(2 * DAY), // Wednesday 25 November, 09:00 UTC
  durationMinutes: 90,
  providerId: 'p1',
  providerName: 'Beauté Divine',
  providerSlug: 'beaute-divine',
  providerPhone: '+225 07 11 22 33 44',
  providerWhatsapp: '+2250711223355',
  providerAddress: 'Rue des Jardins',
  providerCommune: 'Cocody',
  providerCity: 'Abidjan',
  providerLatitude: 5.3599,
  providerLongitude: -3.9871,
  providerPhotoUrl: 'https://cdn.myweli.com/p1/cover.jpg',
  providerTimezone: 'Africa/Abidjan',
  providerCurrency: 'XOF',
  serviceIds: ['s1', 's2'],
  serviceNames: ['Tresses', 'Soin du visage'],
  artistId: 'a1',
  artistName: 'Awa',
  totalPrice: 25_000,
  depositAmount: 0,
  balanceDue: 25_000,
};

function serve(a: Appointment) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      const path = String(url).split('?')[0];
      if (path === `/api/appointments/${a.id}`) {
        return new Response(JSON.stringify(a), { status: 200 });
      }
      if (path === '/api/localities') {
        // One country, one operator marked Wave: enough for the proof form's
        // « Payer avec Wave » link to draw.
        const tree = {
          countries: [
            {
              code: 'CI',
              name: "Côte d'Ivoire",
              currency: 'XOF',
              phonePrefix: '+225',
              operators: [{ id: 'wave', label: 'Wave', deepLinkKind: 'wave' }],
              cities: [],
            },
          ],
        };
        return new Response(JSON.stringify(tree), { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

async function open(extra: Partial<Appointment> = {}) {
  const a = { ...base, ...extra };
  serve(a);
  render(<AppointmentDetailClient id={a.id} />);
  await screen.findByRole('heading', { level: 1 });
  return a;
}

const section = (title: string) =>
  screen.getByRole('heading', { level: 2, name: title }).closest('section')!;
const link = (name: string) => screen.queryByRole('link', { name });

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(NOW);
});

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe('the header (§2.3)', () => {
  it('the cover, decorative; the name as h1; the client chip and its sentence', async () => {
    await open({ status: 'pending' });
    const img = document.querySelector('img');
    expect(img).not.toBeNull();
    expect(img!.getAttribute('alt')).toBe('');
    expect(img!.closest('div')!.className).toContain('aspect-cover');
    expect(screen.getByRole('heading', { level: 1, name: 'Beauté Divine' })).toBeInTheDocument();
    expect(screen.getByText('En attente')).toBeInTheDocument();
    expect(screen.getByText('Le salon doit encore confirmer ce rendez-vous.')).toBeInTheDocument();
  });

  it('a stopped salon: no cover, even if one were sent (the page holds the rule)', async () => {
    await open({ providerStatus: 'suspended' });
    expect(document.querySelector('img')).toBeNull();
  });

  it('no photo, or not https: no image block', async () => {
    await open({ providerPhotoUrl: null });
    expect(document.querySelector('img')).toBeNull();
    cleanup();
    await open({ providerPhotoUrl: 'asset:assets/x.png' });
    expect(document.querySelector('img')).toBeNull();
  });

  it('the chip is the client chip, drawn with a visible pill (A1w left its tone to A2)', async () => {
    await open({ status: 'pending', appointmentDate: at(-2 * DAY) });
    const chip = screen.getByText('Non confirmé');
    expect(chip.className).toContain('bg-textSecondary/10');
    expect(
      screen.getByText('Le salon n’a pas confirmé ce rendez-vous avant son heure.'),
    ).toBeInTheDocument();
  });
});

describe('the sections (§2.2)', () => {
  it('h1, then one h2 per section, in the app’s order', async () => {
    await open({ notes: 'Cheveux fragiles' });
    const order = screen
      .getAllByRole('heading')
      .map((h) => `${h.tagName}:${h.textContent}`);
    expect(order).toEqual([
      'H1:Beauté Divine',
      'H2:Le rendez-vous',
      'H2:Prestations',
      'H2:Le salon',
      'H2:Paiement',
      'H2:Notes',
    ]);
  });

  it('« Le rendez-vous »: the date with its weekday, the start and the end', async () => {
    await open();
    const s = within(section('Le rendez-vous'));
    expect(s.getByText('mercredi 25 novembre 2026')).toBeInTheDocument();
    expect(s.getByText('09:00 – 10:30')).toBeInTheDocument();
    expect(s.getByText('Awa')).toBeInTheDocument();
  });

  it('a label–value row wraps instead of squeezing its value', async () => {
    await open();
    const dt = within(section('Le rendez-vous')).getByText('Date');
    expect(dt.parentElement!.className).toContain('flex-wrap');
  });

  it('the « heure du salon » hint sits under the time, before the specialist', async () => {
    await open({ providerTimezone: 'Africa/Libreville' });
    const s = section('Le rendez-vous');
    const heure = within(s).getByText('Heure');
    // WAIT for it: the hint is drawn one effect after the page (mount-gated,
    // SalonTimeHint), so a read the moment the h1 appears can come before that
    // effect ran. A synchronous getByText lost it once on CI (run 45636330662);
    // `npm run test:stress` loses it every time.
    const hint = await within(s).findByText(/heure du salon/i);
    const specialist = within(s).getByText('Spécialiste');
    expect(heure.compareDocumentPosition(hint) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(hint.compareDocumentPosition(specialist) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('notes made of spaces are no notes', async () => {
    await open({ notes: '   ' });
    expect(screen.queryByRole('heading', { name: 'Notes' })).toBeNull();
  });

  it('a salon one hour ahead: the times are its own', async () => {
    await open({ providerTimezone: 'Africa/Libreville' });
    expect(within(section('Le rendez-vous')).getByText('10:00 – 11:30')).toBeInTheDocument();
  });

  it('no duration: the start alone', async () => {
    await open({ durationMinutes: undefined });
    expect(within(section('Le rendez-vous')).getByText('09:00')).toBeInTheDocument();
  });

  it('« Prestations »: one list item per service', async () => {
    await open();
    const items = within(section('Prestations')).getAllByRole('listitem');
    expect(items.map((li) => li.textContent)).toEqual(['Tresses', 'Soin du visage']);
  });

  it('a section with nothing to show is left out', async () => {
    await open({
      serviceNames: [],
      providerPhone: null,
      providerWhatsapp: null,
      providerLatitude: null,
      providerLongitude: null,
      providerAddress: null,
      providerCommune: null,
      providerCity: null,
      providerStatus: 'suspended',
    });
    expect(screen.queryByRole('heading', { name: 'Prestations' })).toBeNull();
    expect(screen.queryByRole('heading', { name: 'Le salon' })).toBeNull();
    expect(screen.queryByRole('heading', { name: 'Notes' })).toBeNull();
    expect(screen.getByRole('heading', { name: 'Paiement' })).toBeInTheDocument();
  });
});

describe('« Le salon » (§2.6)', () => {
  it('the address, then « commune, ville », and every way that works', async () => {
    await open();
    const s = within(section('Le salon'));
    expect(s.getByText('Rue des Jardins')).toBeInTheDocument();
    expect(s.getByText('Cocody, Abidjan')).toBeInTheDocument();
    expect(s.getByRole('link', { name: 'Itinéraire' })).toHaveAttribute(
      'href',
      'https://www.google.com/maps/dir/?api=1&destination=5.3599,-3.9871',
    );
    expect(s.getByRole('link', { name: 'Appeler' })).toHaveAttribute('href', 'tel:+2250711223344');
    expect(s.getByRole('link', { name: 'WhatsApp' })).toHaveAttribute(
      'href',
      'https://wa.me/2250711223355',
    );
    expect(s.getByRole('link', { name: 'Voir le salon' })).toHaveAttribute('href', '/beaute-divine');
    for (const name of ['Itinéraire', 'Appeler', 'WhatsApp', 'Voir le salon']) {
      expect(s.getByRole('link', { name }).className, name).toContain('min-h-12');
    }
  });

  it('« Itinéraire » needs a position — a pair', async () => {
    await open({ providerLatitude: null });
    expect(link('Itinéraire')).toBeNull();
    expect(within(section('Le salon')).getByText('Rue des Jardins')).toBeInTheDocument();
  });

  it('a stopped salon keeps the way there, not its page', async () => {
    await open({ providerStatus: 'suspended', providerPhotoUrl: null });
    expect(link('Itinéraire')).not.toBeNull();
    expect(link('Appeler')).not.toBeNull();
    expect(link('WhatsApp')).not.toBeNull();
    expect(link('Voir le salon')).toBeNull();
    expect(screen.queryByRole('button', { name: 'Reporter' })).toBeNull();
    expect(screen.getByRole('button', { name: 'Annuler le rendez-vous' })).toBeInTheDocument();
  });
});

describe('« Paiement » (§2.7)', () => {
  it('a deposit to send, ahead: the proof form, and « Reporter » steps back', async () => {
    await open({ status: 'pending', depositAmount: 5000, balanceDue: 20_000 });
    const s = within(section('Paiement'));
    expect(s.getByText('Acompte à envoyer')).toBeInTheDocument();
    expect(s.getByRole('button', { name: 'Envoyer la preuve' })).toBeInTheDocument();
    expect(s.getByText('Solde à régler au salon')).toBeInTheDocument();
    // One primary per state: money first.
    expect(screen.getByRole('button', { name: 'Reporter' }).className).not.toContain('bg-primary');
  });

  it('« Payer avec Wave » reaches the 48 px floor', async () => {
    await open({
      status: 'pending',
      depositAmount: 5000,
      balanceDue: 20_000,
      depositMobileMoneyOperator: 'wave',
      depositMobileMoneyNumber: '+2250700000000',
    });
    const wave = screen.getByRole('link', { name: /Payer avec Wave/ });
    expect(wave.className).toContain('min-h-12');
    expect(wave.className).not.toContain('py-xs');
  });

  it('no proof form once the time has passed', async () => {
    await open({
      status: 'pending',
      appointmentDate: at(-2 * DAY),
      depositAmount: 5000,
      balanceDue: 20_000,
    });
    const s = within(section('Paiement'));
    expect(s.getByText('Aucun justificatif envoyé')).toBeInTheDocument();
    expect(s.queryByRole('button', { name: 'Envoyer la preuve' })).toBeNull();
  });

  it('a status this build does not know: closed — the amount, no form, no balance', async () => {
    await open({ status: 'onHold', depositAmount: 5000, balanceDue: 20_000 });
    const s = within(section('Paiement'));
    expect(s.getByText('Acompte')).toBeInTheDocument();
    expect(s.queryByRole('button', { name: 'Envoyer la preuve' })).toBeNull();
    expect(s.queryByText('Solde à régler au salon')).toBeNull();
  });

  it('a booking the salon entered: no deposit block, whatever it carries', async () => {
    await open({ status: 'pending', salonEntered: true, depositAmount: 5000 });
    const s = within(section('Paiement'));
    expect(s.queryByText('Acompte à envoyer')).toBeNull();
    expect(s.queryByRole('button', { name: 'Envoyer la preuve' })).toBeNull();
  });

  it('never « Acompte confirmé »', async () => {
    await open({ depositAmount: 5000, balanceDue: 20_000 });
    expect(screen.queryByText('Acompte confirmé')).toBeNull();
    expect(within(section('Paiement')).getByText('Acompte')).toBeInTheDocument();
  });

  it('a cancelled booking: no balance; the no-custody sentence; « Voir ma capture »', async () => {
    await open({
      status: 'cancelled',
      depositAmount: 5000,
      balanceDue: 20_000,
      depositScreenshotUrl: 'deposit/u1/p.jpg',
    });
    const s = within(section('Paiement'));
    expect(s.queryByText('Solde à régler au salon')).toBeNull();
    // The exact text, no-break space included (the matcher normalises
    // whitespace, which would hide a regular space there).
    expect(
      [...section('Paiement').querySelectorAll('p')].some(
        (p) => p.textContent === DEPOSIT_SEE_THE_SALON,
      ),
    ).toBe(true);
    expect(DEPOSIT_SEE_THE_SALON).toContain('salon\u00a0:');
    expect(s.getByRole('link', { name: 'Voir ma capture' }).className).toContain('min-h-12');
  });
});

describe('the actions (§2.8)', () => {
  it('a completed visit: « Réserver à nouveau » is the one primary outside the review form', async () => {
    await open({ status: 'completed', appointmentDate: at(-2 * DAY) });
    const form = screen.getByRole('button', { name: /Envoyer l.avis/ }).closest('form, div');
    const primaries = [...document.querySelectorAll('a, button')].filter(
      (el) => el.className.includes('bg-primary text-secondary') && !form?.contains(el),
    );
    // The spec's table (§2.8): the review form keeps its own submit button.
    expect(primaries.map((el) => el.textContent)).toEqual(['Réserver à nouveau']);
  });

  it('a past booking: « Réserver à nouveau » is the one primary', async () => {
    await open({ appointmentDate: at(-2 * DAY) });
    const primaries = [...document.querySelectorAll('a, button')].filter((el) =>
      el.className.includes('bg-primary text-secondary'),
    );
    expect(primaries.map((el) => el.textContent)).toEqual(['Réserver à nouveau']);
  });
});

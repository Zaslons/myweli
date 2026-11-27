import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const routerMock = { replace, push: vi.fn(), refresh: vi.fn(), back: vi.fn(), prefetch: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => window.location.pathname,
  useSearchParams: () => new URLSearchParams(window.location.search),
  useParams: () => ({}),
}));

import { RevenueLedgerClient } from '../components/pro/RevenueLedgerClient';
import { ledger, ledgerRow, stubRevenueFetch } from './revenue-fixtures';

/// docs/design/pro-revenue-analytics.md §4.9, §5.1, §21.1 item 11 — « Rendez-
/// vous », the bookings behind a figure, on the website.

const ok = (body: unknown) => ({ status: 200, body });

function at(path: string) {
  window.history.replaceState(null, '', path);
}

beforeEach(() => at('/pro/revenus/rendez-vous'));

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.useRealTimers();
  replace.mockReset();
});

const rows = (n: number, from = 0) =>
  Array.from({ length: n }, (_, i) =>
    ledgerRow({ appointmentId: `appointment_${from + i}`, clientDisplayName: `Cliente ${from + i}` }),
  );

describe('the ledger', () => {
  it('pages of 20; « Afficher plus » asks the next at the same instant, and says how many', async () => {
    const f = stubRevenueFetch({
      ledger: [ok(ledger(rows(20), { total: 23 })), ok(ledger(rows(3, 20), { page: 2, total: 23 }))],
    });
    render(<RevenueLedgerClient />);
    expect(await screen.findByText(/^20 sur 23\srendez-vous$/)).toHaveAttribute('role', 'status');
    fireEvent.click(screen.getByRole('button', { name: 'Afficher plus' }));
    expect(await screen.findByText(/^23 sur 23\srendez-vous$/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Afficher plus' })).toBeNull();
    const [first, second] = f.ledgerAsked();
    expect(first.get('page')).toBe('1');
    expect(first.get('pageSize')).toBe('20');
    expect(second.get('page')).toBe('2');
    // The next pages count against the first page's own instant.
    expect(second.get('asOf')).toBe('2026-11-27T09:05:54.000Z');
  });

  it('a row: salon time, client, prestations, collaborateur; the line « sur » its total; it opens the booking', async () => {
    stubRevenueFetch({
      ledger: ok(
        ledger([
          ledgerRow({ amount: 15000, totalPrice: 35000, serviceNames: ['Tresses', 'Soin'], estimated: true }),
        ]),
      ),
    });
    render(<RevenueLedgerClient />);
    const link = await screen.findByRole('link', { name: 'Ouvrir le rendez-vous du mer. 25 nov. · 14:30' });
    expect(link).toHaveAttribute('href', '/pro/rendez-vous/appointment_1?salon=p1');
    const r = link.closest('[role="row"]') as HTMLElement;
    expect(within(r).getByText('Fatou B.')).toBeInTheDocument();
    expect(within(r).getByText('Tresses, Soin')).toBeInTheDocument();
    expect(within(r).getByText('Awa Koné')).toBeInTheDocument();
    expect(within(r).getByText(/15\s000 FCFA/)).toBeInTheDocument();
    expect(within(r).getByText('· estimé', { exact: false })).toBeInTheDocument();
    expect(within(r).getByText(/^sur 35\s000 FCFA$/)).toBeInTheDocument();
  });

  it('the filters: « Terminés » first; another asks again and lives in the address', async () => {
    at('/pro/revenus/rendez-vous?periode=semaine&date=2026-11-24&collaborateur=artist_awa&salon=p1');
    const f = stubRevenueFetch({ ledger: [ok(ledger(rows(1))), ok(ledger([]))] });
    render(<RevenueLedgerClient />);
    const group = await screen.findByRole('group', { name: 'Statut des rendez-vous' });
    expect(within(group).getByRole('button', { name: 'Terminés' })).toHaveAttribute('aria-pressed', 'true');
    // Named from the team, with the period — no name ever rides in the address.
    expect(screen.getByText('Awa Koné · 23 – 29 nov. 2026')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Awa Koné$/ })).toHaveAttribute(
      'href',
      '/pro/revenus/collaborateurs/artist_awa?periode=semaine&date=2026-11-24&salon=p1',
    );
    fireEvent.click(within(group).getByRole('button', { name: 'Absents' }));
    expect(await screen.findByText('Aucune absence sur cette période.')).toBeInTheDocument();
    expect(f.ledgerAsked()[1].get('status')).toBe('noShow');
    expect(f.ledgerAsked()[1].get('artistId')).toBe('artist_awa');
    expect(window.location.search).toBe(
      '?periode=semaine&date=2026-11-24&collaborateur=artist_awa&statut=absents&salon=p1',
    );
  });

  it('« À clôturer » counts at the banner’s instant — unless the link is older than 23 hours', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-11-27T12:00:00.000Z'));
    at('/pro/revenus/rendez-vous?statut=a-cloturer&instant=2026-11-27T09%3A05%3A53.900Z&salon=p1');
    let f = stubRevenueFetch({ ledger: ok(ledger([])) });
    render(<RevenueLedgerClient />);
    await screen.findByText('Aucun rendez-vous à clôturer sur cette période.');
    expect(f.ledgerAsked()[0].get('status')).toBe('toClose');
    expect(f.ledgerAsked()[0].get('asOf')).toBe('2026-11-27T09:05:53.900Z');
    cleanup();

    vi.setSystemTime(new Date('2026-11-28T09:06:00.000Z'));
    at('/pro/revenus/rendez-vous?statut=a-cloturer&instant=2026-11-27T09%3A05%3A53.900Z&salon=p1');
    f = stubRevenueFetch({ ledger: ok(ledger([])) });
    render(<RevenueLedgerClient />);
    await screen.findByText('Aucun rendez-vous à clôturer sur cette période.');
    expect(f.ledgerAsked()[0].has('asOf')).toBe(false);
  });

  it('refused: « Réservé au propriétaire », no filters', async () => {
    stubRevenueFetch({ ledger: { status: 403, body: { error: 'forbidden' } } });
    render(<RevenueLedgerClient />);
    expect(await screen.findByText('Réservé au propriétaire')).toBeInTheDocument();
    expect(screen.queryByRole('group', { name: 'Statut des rendez-vous' })).toBeNull();
  });

  it('a failure: « Réessayer » asks the same page again', async () => {
    const f = stubRevenueFetch({ ledger: [{ status: 500 }, ok(ledger(rows(1)))] });
    render(<RevenueLedgerClient />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Chargement impossible.');
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    await screen.findByText('Cliente 0');
    expect(f.ledgerAsked()[1].toString()).toBe(f.ledgerAsked()[0].toString());
  });

  it('« Afficher plus » cut: the rows stay, the error says why', async () => {
    stubRevenueFetch({ ledger: [ok(ledger(rows(20), { total: 30 })), 'throw'] });
    render(<RevenueLedgerClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Afficher plus' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Pas de connexion. Réessayez.');
    expect(screen.getByText('Cliente 19')).toBeInTheDocument();
  });

  it('arriving on a bare address does not rewrite it', async () => {
    const spy = vi.spyOn(window.history, 'replaceState');
    stubRevenueFetch({ ledger: ok(ledger(rows(1))) });
    render(<RevenueLedgerClient />);
    await screen.findByText('Cliente 0');
    expect(spy).not.toHaveBeenCalled();
    spy.mockRestore();
  });

  it('another salon’s ledger goes back to « Revenus »', async () => {
    at('/pro/revenus/rendez-vous?periode=jour&salon=p9');
    const f = stubRevenueFetch({ ledger: ok(ledger([])) });
    render(<RevenueLedgerClient />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro/revenus?periode=jour'));
    expect(f.ledgerAsked()).toHaveLength(0);
  });
});

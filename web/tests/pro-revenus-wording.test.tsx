import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn(), back: vi.fn(), prefetch: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => window.location.pathname,
  useSearchParams: () => new URLSearchParams(window.location.search),
  useParams: () => ({}),
}));

import { RevenueLedgerClient } from '../components/pro/RevenueLedgerClient';
import { RevenueDetailClient } from '../components/pro/RevenueDetailClient';
import { RevenusClient } from '../components/pro/RevenusClient';
import { ledger, r2, stubRevenueFetch } from './revenue-fixtures';

/// « Revenus » never says MyWeli took a payment (docs/design/pro-revenue-
/// analytics.md §4.10, §21.1 item 10; PRD OQ-1): no « encaissé »,
/// « encaissement », « chiffre d'affaires », « paiements reçus ». The one
/// « encaiss » on the page is the footnote's negation — « MyWeli n'encaisse
/// rien ». Read on the R2 server's own answers, every tab.

const FORBIDDEN = /encaissé|encaissement|chiffre d.affaires|paiements reçus/i;

function expectNoPaymentWords() {
  const text = document.body.textContent ?? '';
  expect(text).not.toMatch(FORBIDDEN);
  // Every « encaiss » is the footnote's own « n'encaisse rien ».
  const all = text.match(/encaiss\w*/gi) ?? [];
  const negations = text.match(/n.encaisse rien/gi) ?? [];
  expect(all.length).toBe(negations.length);
}

const ok = (body: unknown) => ({ status: 200, body });

beforeEach(() => window.history.replaceState(null, '', '/pro/revenus'));

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('« Revenus » — the words', () => {
  it('the overview, on each tab: « Réalisé », and MyWeli takes nothing', async () => {
    stubRevenueFetch({ revenue: ok(r2('analytics_month')), ledger: ok(r2('ledger_completed')) });
    render(<RevenusClient />);
    const tabs = await screen.findByRole('group', { name: 'Répartition' });
    expect(screen.getByText(/MyWeli n’encaisse rien\.$/)).toBeInTheDocument();
    expect(screen.getAllByText('Réalisé').length).toBeGreaterThan(0);
    for (const name of ['Collaborateurs', 'Prestations', 'Canaux']) {
      fireEvent.click(within(tabs).getByRole('button', { name }));
      expectNoPaymentWords();
    }
    fireEvent.click(screen.getByRole('button', { name: 'Voir les données' }));
    expectNoPaymentWords();
  });

  it('a prestation’s detail', async () => {
    window.history.replaceState(null, '', '/pro/revenus/prestations/svc-Tresses?salon=p1');
    stubRevenueFetch({
      revenue: ok(r2('analytics_month_service_svc-Tresses')),
      ledger: ok(r2('ledger_completed')),
    });
    render(<RevenueDetailClient axis="service" filterKey="svc-Tresses" />);
    await screen.findByRole('group', { name: 'Répartition' });
    expectNoPaymentWords();
  });

  it('the ledger, on each filter — its rows, then each empty sentence', async () => {
    window.history.replaceState(null, '', '/pro/revenus/rendez-vous?salon=p1');
    // The rows first; then every other filter answers empty, so its own
    // sentence is on screen when the words are read — never a skeleton (the
    // review found this test reading only skeletons: the chips render before
    // the answer, and a click shows the skeleton at once).
    stubRevenueFetch({ ledger: [ok(r2('ledger_completed')), ok(ledger([]))] });
    render(<RevenueLedgerClient />);
    await screen.findAllByRole('link', { name: /^Ouvrir le rendez-vous du / });
    expectNoPaymentWords();
    const group = screen.getByRole('group', { name: 'Statut des rendez-vous' });
    for (const [name, sentence] of [
      ['À venir', 'Aucun rendez-vous à venir sur cette période.'],
      ['À clôturer', 'Aucun rendez-vous à clôturer sur cette période.'],
      ['Absents', 'Aucune absence sur cette période.'],
      ['Annulés', 'Aucun rendez-vous annulé ou refusé sur cette période.'],
    ] as const) {
      fireEvent.click(within(group).getByRole('button', { name }));
      expect(await screen.findByText(sentence)).toBeInTheDocument();
      expectNoPaymentWords();
    }
  });
});

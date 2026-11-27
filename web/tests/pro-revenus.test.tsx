import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const routerMock = { replace, push: vi.fn(), refresh: vi.fn(), back: vi.fn(), prefetch: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => window.location.pathname,
  useSearchParams: () => new URLSearchParams(window.location.search),
  useParams: () => ({}),
}));

import { RevenueDetailClient } from '../components/pro/RevenueDetailClient';
import { RevenusClient } from '../components/pro/RevenusClient';
import {
  OWNER_PROFILE,
  analytics,
  figures,
  group,
  ledger,
  ledgerRow,
  row,
  stubRevenueFetch,
} from './revenue-fixtures';

/// docs/design/pro-revenue-analytics.md §5, §13.3, §22 — « Revenus » on the
/// website: every state of §4.11, the period bar (stepped from the answer),
/// the address, the chart's keys, the tables, the CSV, the details.

const ok = (body: unknown) => ({ status: 200, body });

/// A response the test releases when it wants (a slow or late answer).
function held(body: unknown) {
  let release!: () => void;
  const gate = new Promise<void>((r) => (release = r));
  const answer = async () => {
    await gate;
    return new Response(JSON.stringify(body), { status: 200 });
  };
  return { answer, release: () => act(async () => release()) };
}

function at(path: string) {
  window.history.replaceState(null, '', path);
}

beforeEach(() => {
  at('/pro/revenus');
  window.sessionStorage.clear();
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  replace.mockReset();
});

const TOCLOSE = analytics({
  groups: [
    group({
      current: figures({
        completedAmount: 50000,
        completedCount: 2,
        averageTicket: 25000,
        toCloseCount: 1,
        toCloseAmount: 10000,
        noShowCount: 1,
        noShowAmount: 15000,
        noShowRate: 1 / 3,
        upcomingAmount: 30000,
        upcomingCount: 2,
        pendingCount: 1,
        pendingAmount: 5000,
      }),
    }),
  ],
});

describe('« Revenus » — the answer, drawn', () => {
  it('the period, its comparison, the figures as sentences', async () => {
    stubRevenueFetch({ revenue: ok(TOCLOSE), ledger: ok(ledger([ledgerRow()])) });
    render(<RevenusClient />);
    expect(await screen.findByRole('heading', { level: 2, name: 'Novembre 2026' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { level: 1, name: 'Revenus' })).toBeInTheDocument();
    expect(screen.getByText('(en cours)')).toBeInTheDocument();
    expect(screen.getByText('Comparé à : 1er – 27 oct. 2026, même avancement')).toBeInTheDocument();
    expect(
      screen.getByText(
        /^Réalisé : 50\s000 FCFA, en hausse de 25\s% par rapport à la période 1er – 27 oct\. 2026, même avancement$/,
      ),
    ).toBeInTheDocument();
    expect(screen.getByText(/^Taux d’absence : 33,3\s%, .*1\sabsence · 15\s000 FCFA$/)).toBeInTheDocument();
    expect(
      screen.getByText(/^Prévu : 30\s000 FCFA, 2\srendez-vous confirmés à venir, \+ 1\sdemande en attente$/),
    ).toBeInTheDocument();
  });

  it('« À clôturer »: the banner, and « Voir » under it opens the ledger on what it counted', async () => {
    stubRevenueFetch({ revenue: ok(TOCLOSE), ledger: ok(ledger([ledgerRow()])) });
    render(<RevenusClient />);
    expect(await screen.findByText(/1\srendez-vous passé à clôturer/)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Voir' })).toHaveAttribute(
      'href',
      '/pro/revenus/rendez-vous?statut=a-cloturer&instant=2026-11-27T09%3A05%3A53.900Z&salon=p1',
    );
  });

  it('the latest five: a second, small request after the figures, at their instant', async () => {
    const f = stubRevenueFetch({ revenue: ok(analytics()), ledger: ok(ledger([ledgerRow()])) });
    render(<RevenusClient />);
    const link = await screen.findByRole('link', { name: /Ouvrir le rendez-vous du mer\. 25 nov\. · 14:30/ });
    expect(link).toHaveAttribute('href', '/pro/rendez-vous/appointment_1?salon=p1');
    const asked = f.ledgerAsked()[0];
    expect(asked.get('pageSize')).toBe('5');
    expect(asked.get('status')).toBe('completed');
    expect(asked.get('asOf')).toBe('2026-11-27T09:05:53.900Z');
    expect(asked.has('compare')).toBe(false);
    expect(screen.getByRole('link', { name: 'Voir tout (2)' })).toHaveAttribute(
      'href',
      '/pro/revenus/rendez-vous?instant=2026-11-27T09%3A05%3A53.900Z&salon=p1',
    );
  });

  it('« Évolution » is one slider: ← → move through the bars, Échap returns to the total, and the period stays', async () => {
    const f = stubRevenueFetch({ revenue: ok(analytics()), ledger: ok(ledger([])) });
    render(<RevenusClient />);
    const chart = await screen.findByRole('slider', { name: 'Évolution du réalisé' });
    expect(chart).toHaveAttribute('aria-valuetext', expect.stringMatching(/^Réalisé sur la période : 50\s000 FCFA · 2\srendez-vous$/));
    // A vertical swipe on the chart scrolls the page (the review: `touch-none`
    // took it on a phone, where the chart is full-width and 160 px tall).
    expect(chart.className).toContain('touch-pan-y');
    expect(chart.className).not.toContain('touch-none');
    const bars = () => Array.from(chart.children).map((b) => (b.className.includes('bg-primary') ? 'primary' : 'other'));
    expect(bars()).toEqual(['primary', 'primary']);
    fireEvent.keyDown(chart, { key: 'ArrowRight' });
    expect(chart).toHaveAttribute('aria-valuetext', expect.stringMatching(/^dim\. 1er nov\. · 20\s000 FCFA · 1\srendez-vous$/));
    expect(chart).toHaveAttribute('aria-valuenow', '1');
    // The chosen bar is told by its fill: it stays `primary`, the others turn
    // `borderStrong` (an outline would be black on black, §4.6).
    expect(bars()).toEqual(['primary', 'other']);
    expect(chart.children[1].className).toContain('bg-borderStrong');
    fireEvent.keyDown(chart, { key: 'End' });
    expect(chart).toHaveAttribute('aria-valuenow', '2');
    fireEvent.keyDown(chart, { key: 'Escape' });
    expect(chart).toHaveAttribute('aria-valuenow', '0');
    fireEvent.keyDown(chart, { key: 'ArrowLeft' });
    expect(chart).toHaveAttribute('aria-valuenow', '2');
    // The chart's arrows are the chart's: no other period was asked.
    expect(f.revenueAsked()).toHaveLength(1);
  });

  it('« Voir les données » swaps the chart for a table', async () => {
    stubRevenueFetch({ revenue: ok(analytics()), ledger: ok(ledger([])) });
    render(<RevenusClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Voir les données' }));
    const table = screen.getByRole('table', { name: 'Évolution du réalisé' });
    expect(within(table).getByRole('rowheader', { name: 'dim. 1er nov.' })).toBeInTheDocument();
    expect(screen.queryByRole('slider')).toBeNull();
    expect(screen.getByRole('button', { name: 'Voir le graphique' })).toBeInTheDocument();
  });

  it('« Répartition »: three tabs, rows open their detail, the tab lives in the address', async () => {
    stubRevenueFetch({ revenue: ok(analytics()), ledger: ok(ledger([])) });
    render(<RevenusClient />);
    const tabs = await screen.findByRole('group', { name: 'Répartition' });
    expect(within(tabs).getByRole('button', { name: 'Collaborateurs' })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByRole('link', { name: 'Ouvrir le détail : Awa Koné' })).toHaveAttribute(
      'href',
      '/pro/revenus/collaborateurs/artist_awa?salon=p1',
    );
    fireEvent.click(within(tabs).getByRole('button', { name: 'Prestations' }));
    expect(screen.getByRole('link', { name: 'Ouvrir le détail : Tresses' })).toHaveAttribute(
      'href',
      '/pro/revenus/prestations/service_tresses?salon=p1',
    );
    expect(window.location.search).toBe('?vue=prestations');
    expect(screen.getByText('Un rendez-vous à plusieurs prestations compte pour chacune.')).toBeInTheDocument();
    // Back to the first tab — the default, never written.
    fireEvent.click(within(tabs).getByRole('button', { name: 'Collaborateurs' }));
    expect(within(tabs).getByRole('button', { name: 'Collaborateurs' })).toHaveAttribute('aria-pressed', 'true');
    expect(window.location.search).toBe('');
    fireEvent.click(within(tabs).getByRole('button', { name: 'Collaborateurs' }));
    expect(window.location.search).toBe('');
  });

  it('a row’s change is heard once, as a sentence', async () => {
    stubRevenueFetch({ revenue: ok(analytics()), ledger: ok(ledger([])) });
    render(<RevenusClient />);
    const link = await screen.findByRole('link', { name: 'Ouvrir le détail : Awa Koné' });
    const cells = within(link.closest('[role="row"]') as HTMLElement).getAllByRole('cell');
    const last = cells[cells.length - 1];
    expect(last).toHaveTextContent(/^↑\+25\s%en hausse de 25\s% par rapport à la période 1er – 27 oct\. 2026, même avancement$/);
    // The badge is hidden from the ear; only the sentence is heard.
    expect(within(last).getByText(/^\+25\s%$/).closest('[aria-hidden="true"]')).not.toBeNull();
  });

  it('a row opens a detail only when the server can be asked about it', async () => {
    stubRevenueFetch({
      revenue: ok(
        analytics({
          groups: [
            group({
              byService: [
                row({ key: 'service_tresses', label: 'Tresses' }),
                // An id the server would refuse (§7.1): no link to a 400.
                row({ key: 'svc-Soin visage', label: 'Soin visage', share: 0 }),
              ],
            }),
          ],
        }),
      ),
      ledger: ok(ledger([])),
    });
    render(<RevenusClient />);
    fireEvent.click(within(await screen.findByRole('group', { name: 'Répartition' })).getByRole('button', { name: 'Prestations' }));
    expect(screen.getByRole('link', { name: 'Ouvrir le détail : Tresses' })).toBeInTheDocument();
    expect(screen.getByText('Soin visage')).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Ouvrir le détail : Soin visage' })).toBeNull();
  });

  it('« Trier par »: the app’s three choices; the sort lives in the address', async () => {
    const body = analytics({
      groups: [
        group({
          byArtist: [
            row({ key: 'artist_zoe', label: 'Zoé', current: { completedAmount: 40000, completedCount: 1, averageTicket: 40000 } }),
            row({ key: 'artist_awa', label: 'Awa Koné', current: { completedAmount: 10000, completedCount: 1, averageTicket: 10000 } }),
          ],
        }),
      ],
    });
    stubRevenueFetch({ revenue: ok(body), ledger: ok(ledger([])) });
    render(<RevenusClient />);
    const names = () =>
      screen.getAllByRole('link', { name: /^Ouvrir le détail : / }).map((l) => l.getAttribute('aria-label'));
    await screen.findByLabelText('Trier par');
    expect(names()).toEqual(['Ouvrir le détail : Zoé', 'Ouvrir le détail : Awa Koné']);
    fireEvent.change(screen.getByLabelText('Trier par'), { target: { value: 'name' } });
    expect(names()).toEqual(['Ouvrir le détail : Awa Koné', 'Ouvrir le détail : Zoé']);
    expect(window.location.search).toBe('?tri=nom');
  });

  it('« Exporter (CSV) » downloads the table on screen, named after it and the period', async () => {
    stubRevenueFetch({ revenue: ok(analytics()), ledger: ok(ledger([ledgerRow()])) });
    let blob: Blob | null = null;
    const create = vi.fn((b: Blob) => {
      blob = b;
      return 'blob:revenus';
    });
    // jsdom has no object URLs: the page's two calls are given one.
    Object.defineProperty(URL, 'createObjectURL', { value: create, configurable: true });
    Object.defineProperty(URL, 'revokeObjectURL', { value: vi.fn(), configurable: true });
    let filename = '';
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (this: HTMLAnchorElement) {
      filename = this.download;
    });
    render(<RevenusClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Exporter (CSV)' }));
    expect(filename).toBe('revenus-collaborateurs-2026-11.csv');
    // jsdom's Blob has no text(): read it as a browser would.
    const text = await new Promise<string>((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.readAsText(blob!);
    });
    expect(text).toContain('Nom;Rendez-vous terminés;Réalisé');
    expect(text).toContain('Awa Koné;2;50000;100,00;25000;40000;XOF;non');
    expect(text).not.toContain('Fatou');
  });
});

describe('« Revenus » — the period bar', () => {
  it('another kind keeps « now »; the title changes before the answer', async () => {
    const week = held(analytics({ period: 'week', from: '2026-11-23', to: '2026-11-29' }));
    const f = stubRevenueFetch({ revenue: [ok(analytics()), week.answer], ledger: ok(ledger([])) });
    render(<RevenusClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Semaine' }));
    expect(screen.getByRole('heading', { level: 2, name: '23 – 29 nov. 2026' })).toBeInTheDocument();
    // The old figures never stand under the new title.
    expect(screen.queryByText(/^Réalisé : /)).toBeNull();
    expect(f.revenueAsked()[1].toString()).toBe('period=week&compare=previous&providerId=p1');
    await week.release();
    expect(window.location.search).toBe('?periode=semaine');
  });

  it('‹ › step from the answer; ← → too — but not from a list or a field', async () => {
    const f = stubRevenueFetch({ revenue: ok(analytics()), ledger: ok(ledger([])) });
    render(<RevenusClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Période précédente' }));
    await screen.findByRole('slider');
    expect(f.revenueAsked()[1].get('date')).toBe('2026-10-01');
    fireEvent.keyDown(document.body, { key: 'ArrowRight' });
    await screen.findByRole('slider');
    expect(f.revenueAsked()[2].get('date')).toBe('2026-12-01');
    fireEvent.keyDown(document.body, { key: 'ArrowRight', repeat: true });
    fireEvent.keyDown(document.body, { key: 'ArrowRight', shiftKey: true });
    fireEvent.keyDown(screen.getByLabelText('Comparer à'), { key: 'ArrowLeft' });
    expect(f.revenueAsked()).toHaveLength(3);
  });

  it('‹ › wait for the answer without being disabled — a keyboard user keeps focus', async () => {
    const slow = held(analytics({ from: '2026-10-01', to: '2026-10-31', inProgress: false }));
    stubRevenueFetch({ revenue: [ok(analytics()), slow.answer], ledger: ok(ledger([])) });
    render(<RevenusClient />);
    const next = await screen.findByRole('button', { name: 'Période suivante' });
    const previous = screen.getByRole('button', { name: 'Période précédente' });
    previous.focus();
    fireEvent.click(previous);
    // Waiting: announced as unavailable, never `disabled` (a disabled button
    // drops focus to the page).
    expect(previous).toHaveAttribute('aria-disabled', 'true');
    expect(previous).not.toHaveAttribute('disabled');
    expect(next).not.toHaveAttribute('disabled');
    expect(document.activeElement).toBe(previous);
    await slow.release();
    await waitFor(() => expect(previous).toHaveAttribute('aria-disabled', 'false'));
  });

  it('an address in another encoding is asked once', async () => {
    at('/pro/revenus?periode=annee&x=a%20b');
    const f = stubRevenueFetch({
      revenue: ok(analytics({ period: 'year', from: '2026-01-01', to: '2026-12-31', bucket: 'month' })),
      ledger: ok(ledger([])),
    });
    render(<RevenusClient />);
    await screen.findByRole('slider');
    await new Promise((r) => setTimeout(r, 50));
    expect(f.revenueAsked()).toHaveLength(1);
    expect(window.location.search).toBe('?periode=annee');
  });

  it('a late answer of an older period is dropped', async () => {
    const slow = held(analytics());
    stubRevenueFetch({
      revenue: [ok(analytics()), slow.answer, ok(analytics({ period: 'year', from: '2026-01-01', to: '2026-12-31', bucket: 'month' }))],
      ledger: ok(ledger([])),
    });
    render(<RevenusClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Semaine' }));
    fireEvent.click(screen.getByRole('button', { name: 'Année' }));
    expect(await screen.findByRole('heading', { level: 2, name: '2026' })).toBeInTheDocument();
    await slow.release();
    expect(screen.getByRole('heading', { level: 2, name: '2026' })).toBeInTheDocument();
    expect(screen.queryByRole('heading', { level: 2, name: 'Novembre 2026' })).toBeNull();
  });

  it('« Comparer à » asks again, and is kept for the session and in the address', async () => {
    const f = stubRevenueFetch({ revenue: ok(analytics()), ledger: ok(ledger([])) });
    render(<RevenusClient />);
    fireEvent.change(await screen.findByLabelText('Comparer à'), { target: { value: 'year' } });
    await waitFor(() => expect(f.revenueAsked()).toHaveLength(2));
    expect(f.revenueAsked()[1].get('compare')).toBe('year');
    expect(window.sessionStorage.getItem('myweli.pro.revenus.comparer')).toBe('year');
    expect(window.location.search).toBe('?comparer=annee');
  });

  it('the session’s comparison applies to an address that does not say', async () => {
    window.sessionStorage.setItem('myweli.pro.revenus.comparer', 'none');
    const f = stubRevenueFetch({ revenue: ok(analytics()), ledger: ok(ledger([])) });
    render(<RevenusClient />);
    await screen.findByRole('slider');
    expect(f.revenueAsked()[0].get('compare')).toBe('none');
  });

  it('an address says the period, the tab and the sort', async () => {
    at('/pro/revenus?periode=annee&date=2025-03-01&comparer=aucune&vue=canaux&tri=nom');
    const f = stubRevenueFetch({
      revenue: ok(analytics({ period: 'year', from: '2025-01-01', to: '2025-12-31', inProgress: false, bucket: 'month' })),
      ledger: ok(ledger([])),
    });
    render(<RevenusClient />);
    const tabs = await screen.findByRole('group', { name: 'Répartition' });
    expect(f.revenueAsked()[0].toString()).toBe('period=year&date=2025-03-01&compare=none&providerId=p1');
    expect(within(tabs).getByRole('button', { name: 'Canaux' })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByLabelText('Trier par')).toHaveValue('name');
  });

  it('a malformed address is the current month, without an error', async () => {
    at('/pro/revenus?periode=trimestre&date=hier');
    const f = stubRevenueFetch({ revenue: ok(analytics()), ledger: ok(ledger([])) });
    render(<RevenusClient />);
    await screen.findByRole('slider');
    expect(f.revenueAsked()[0].toString()).toBe('period=month&compare=previous&providerId=p1');
    expect(window.location.search).toBe('');
  });

  it('« Dates… »: the error is under « Au », tied to it; a good range is asked', async () => {
    const f = stubRevenueFetch({ revenue: ok(analytics()), ledger: ok(ledger([])) });
    render(<RevenusClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Dates…' }));
    const dialog = screen.getByRole('dialog', { name: 'Choisir les dates' });
    fireEvent.change(within(dialog).getByLabelText('Du'), { target: { value: '2026-11-10' } });
    fireEvent.change(within(dialog).getByLabelText('Au'), { target: { value: '2026-11-01' } });
    const au = within(dialog).getByLabelText('Au');
    expect(au).toHaveAttribute('aria-invalid', 'true');
    expect(au).toHaveAccessibleDescription('La date de fin précède la date de début');
    fireEvent.click(within(dialog).getByRole('button', { name: 'Afficher' }));
    expect(f.revenueAsked()).toHaveLength(1);
    fireEvent.change(au, { target: { value: '2026-11-20' } });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Afficher' }));
    await waitFor(() => expect(f.revenueAsked()).toHaveLength(2));
    expect(f.revenueAsked()[1].toString()).toBe('period=custom&from=2026-11-10&to=2026-11-20&compare=previous&providerId=p1');
    expect(screen.queryByRole('dialog')).toBeNull();
  });
});

describe('« Revenus » — every state (§4.11)', () => {
  it('a salon with nothing completed, ever: the banner and « Prévu » still above « Pas encore de revenus »', async () => {
    stubRevenueFetch({
      revenue: ok(
        analytics({
          everCompleted: false,
          groups: [
            group({
              current: figures({ upcomingAmount: 20000, upcomingCount: 1, toCloseCount: 2, toCloseAmount: 30000 }),
              previous: figures(),
              byArtist: [],
              byService: [],
              byChannel: [],
            }),
          ],
        }),
      ),
    });
    render(<RevenusClient />);
    expect(await screen.findByText('Pas encore de revenus')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Voir les rendez-vous' })).toHaveAttribute('href', '/pro/rendez-vous');
    expect(screen.getByText(/2\srendez-vous passés à clôturer/)).toBeInTheDocument();
    expect(screen.getByText(/^Prévu : 20\s000 FCFA/)).toBeInTheDocument();
  });

  it('a period with nothing completed: « Période précédente » asks the one before', async () => {
    const f = stubRevenueFetch({
      revenue: ok(analytics({ groups: [group({ current: figures(), previous: figures(), series: [], byArtist: [], byService: [], byChannel: [] })] })),
    });
    render(<RevenusClient />);
    expect(await screen.findByText('Aucun rendez-vous terminé sur cette période')).toBeInTheDocument();
    expect(screen.queryByRole('slider')).toBeNull();
    // The empty state's own button (the bar's ‹ has the same name, and does
    // the same).
    const buttons = screen.getAllByRole('button', { name: 'Période précédente' });
    expect(buttons).toHaveLength(2);
    fireEvent.click(buttons[1]);
    await waitFor(() => expect(f.revenueAsked()).toHaveLength(2));
    expect(f.revenueAsked()[1].get('date')).toBe('2026-10-01');
  });

  it('a period not begun says so', async () => {
    stubRevenueFetch({
      revenue: ok(
        analytics({
          from: '2026-12-01',
          to: '2026-12-31',
          inProgress: false,
          groups: [group({ current: figures({ upcomingAmount: 10000, upcomingCount: 1 }), previous: figures(), series: [], byArtist: [], byService: [], byChannel: [] })],
        }),
      ),
    });
    render(<RevenusClient />);
    expect(await screen.findByText('Rien de terminé pour l’instant')).toBeInTheDocument();
  });

  it('refused (403): « Réservé au propriétaire », no period bar, nothing to retry', async () => {
    stubRevenueFetch({ revenue: { status: 403, body: { error: 'forbidden' } } });
    render(<RevenusClient />);
    expect(await screen.findByText('Réservé au propriétaire')).toBeInTheDocument();
    expect(screen.getByText('Seul le propriétaire du salon voit les revenus.')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Semaine' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Réessayer' })).toBeNull();
  });

  it('a failure: « Réessayer » asks the same period again', async () => {
    at('/pro/revenus?periode=semaine&date=2026-11-02');
    const f = stubRevenueFetch({
      revenue: [{ status: 500, body: { error: 'internal' } }, ok(analytics({ period: 'week', from: '2026-11-02', to: '2026-11-08', inProgress: false }))],
      ledger: ok(ledger([])),
    });
    render(<RevenusClient />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Chargement impossible.');
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    await screen.findByRole('heading', { level: 2, name: '2 – 8 nov. 2026' });
    expect(f.revenueAsked()[1].toString()).toBe(f.revenueAsked()[0].toString());
  });

  it('an unreadable answer is an error, never a page of zeros', async () => {
    stubRevenueFetch({ revenue: ok({ ...analytics(), groups: 'none' }) });
    render(<RevenusClient />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Pas de connexion. Réessayez.');
    expect(screen.queryByText(/^Réalisé : /)).toBeNull();
  });

  it('two currencies: one at a time, never added', async () => {
    stubRevenueFetch({
      revenue: ok(
        analytics({
          groups: [
            group(),
            group({
              currency: 'XAF',
              current: figures({ completedAmount: 7000, completedCount: 1, averageTicket: 7000 }),
              previous: null,
            }),
          ],
        }),
      ),
      ledger: ok(ledger([])),
    });
    render(<RevenusClient />);
    const currencies = await screen.findByRole('group', { name: 'Devise' });
    expect(screen.getByText(/^Réalisé : 50\s000 FCFA/)).toBeInTheDocument();
    fireEvent.click(within(currencies).getByRole('button', { name: 'XAF · franc CFA (CEMAC)' }));
    expect(screen.getByText(/^Réalisé : 7\s000 FCFA$/)).toBeInTheDocument();
    expect(screen.queryByText(/57\s000/)).toBeNull();
  });

  it('signed out (401) → the pro sign-in', async () => {
    stubRevenueFetch({ me: { status: 401 } });
    render(<RevenusClient />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro/connexion'));
  });
});

describe('a detail (§4.8, §5.4)', () => {
  const awa = analytics({
    filters: { artistId: 'artist_awa', serviceId: null, channel: null, label: 'Awa Koné', state: 'active' },
    groups: [group({ byArtist: [] })],
  });

  it('a collaborateur: the name heads the page, the other axes are the tabs, a row opens one level more', async () => {
    at('/pro/revenus/collaborateurs/artist_awa?salon=p1');
    const f = stubRevenueFetch({ revenue: ok(awa), ledger: ok(ledger([ledgerRow()])) });
    render(<RevenueDetailClient axis="artist" filterKey="artist_awa" />);
    expect(await screen.findByRole('heading', { level: 1, name: 'Awa Koné' })).toBeInTheDocument();
    expect(screen.getByText('Collaborateur', { selector: 'p' })).toBeInTheDocument();
    expect(f.revenueAsked()[0].get('artistId')).toBe('artist_awa');
    const tabs = await screen.findByRole('group', { name: 'Répartition' });
    expect(within(tabs).queryByRole('button', { name: 'Collaborateurs' })).toBeNull();
    expect(within(tabs).getByRole('button', { name: 'Prestations' })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByRole('link', { name: 'Ouvrir le détail : Tresses' })).toHaveAttribute(
      'href',
      '/pro/revenus/prestations/service_tresses?collaborateur=artist_awa&salon=p1',
    );
    expect(screen.getByRole('link', { name: /Revenus$/ })).toHaveAttribute('href', '/pro/revenus');
    expect(screen.getByRole('link', { name: 'Voir tout (2)' })).toHaveAttribute(
      'href',
      '/pro/revenus/rendez-vous?collaborateur=artist_awa&instant=2026-11-27T09%3A05%3A53.900Z&depuis=collaborateur&salon=p1',
    );
  });

  it('inside a detail: both filters asked, the parent named and linked, no deeper', async () => {
    at('/pro/revenus/prestations/service_tresses?periode=semaine&date=2026-11-24&collaborateur=artist_awa&salon=p1');
    const f = stubRevenueFetch({
      revenue: ok({
        ...awa,
        period: 'week',
        from: '2026-11-23',
        to: '2026-11-29',
        filters: { artistId: 'artist_awa', serviceId: 'service_tresses', channel: null, label: 'Awa Koné', state: 'active' },
        groups: [group({ byArtist: [], byService: [] })],
      }),
      ledger: ok(ledger([])),
    });
    render(<RevenueDetailClient axis="service" filterKey="service_tresses" />);
    expect(await screen.findByRole('heading', { level: 1, name: 'Tresses' })).toBeInTheDocument();
    expect(screen.getByText('Prestation · Awa Koné')).toBeInTheDocument();
    const asked = f.revenueAsked()[0];
    expect(asked.get('artistId')).toBe('artist_awa');
    expect(asked.get('serviceId')).toBe('service_tresses');
    expect(screen.getByRole('link', { name: /Awa Koné$/ })).toHaveAttribute(
      'href',
      '/pro/revenus/collaborateurs/artist_awa?periode=semaine&date=2026-11-24&salon=p1',
    );
    await screen.findByRole('group', { name: 'Répartition' });
    expect(screen.queryByRole('link', { name: /^Ouvrir le détail/ })).toBeNull();
    // Its CSV names both rows: « Tresses » alone is another table.
    Object.defineProperty(URL, 'createObjectURL', { value: () => 'blob:x', configurable: true });
    Object.defineProperty(URL, 'revokeObjectURL', { value: () => undefined, configurable: true });
    let filename = '';
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (this: HTMLAnchorElement) {
      filename = this.download;
    });
    fireEvent.click(screen.getByRole('button', { name: 'Exporter (CSV)' }));
    expect(filename).toBe('revenus-awa-kone-tresses-canaux-2026-11-23_2026-11-29.csv');
  });

  it('a collaborateur who left keeps the name the server kept', async () => {
    at('/pro/revenus/collaborateurs/artist_parti?salon=p1');
    stubRevenueFetch({
      revenue: ok({
        ...awa,
        filters: { artistId: 'artist_parti', serviceId: null, channel: null, label: 'Konan Serge', state: 'removed' },
      }),
      ledger: ok(ledger([])),
    });
    render(<RevenueDetailClient axis="artist" filterKey="artist_parti" />);
    expect(
      await screen.findByRole('heading', { level: 1, name: 'Konan Serge · a quitté l’équipe' }),
    ).toBeInTheDocument();
  });

  it('arriving on a bare address does not rewrite it (a rewrite is a navigation: the title would be read out)', async () => {
    at('/pro/revenus/collaborateurs/artist_awa');
    const spy = vi.spyOn(window.history, 'replaceState');
    stubRevenueFetch({ revenue: ok(awa), ledger: ok(ledger([])) });
    render(<RevenueDetailClient axis="artist" filterKey="artist_awa" />);
    await screen.findByRole('heading', { level: 1, name: 'Awa Koné' });
    await screen.findByRole('group', { name: 'Répartition' });
    expect(spy).not.toHaveBeenCalled();
    expect(window.location.search).toBe('');
  });

  it('another salon’s detail (after a switch) goes back to « Revenus », same period', async () => {
    at('/pro/revenus/collaborateurs/artist_awa?periode=annee&salon=p9');
    const f = stubRevenueFetch({ revenue: ok(awa) });
    render(<RevenueDetailClient axis="artist" filterKey="artist_awa" />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro/revenus?periode=annee'));
    expect(f.revenueAsked()).toHaveLength(0);
  });
});

describe('the profile behind the page', () => {
  it('reads the active salon’s id from /me', async () => {
    const f = stubRevenueFetch({
      me: { status: 200, body: { ...OWNER_PROFILE, provider: { ...OWNER_PROFILE.provider, id: 'p2' } } },
      revenue: ok(analytics()),
      ledger: ok(ledger([])),
    });
    render(<RevenusClient />);
    await screen.findByRole('slider');
    expect(f.revenueAsked()[0].get('providerId')).toBe('p2');
  });
});

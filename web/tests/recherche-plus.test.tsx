import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// The search's map is behind next/dynamic, out of this test's reach, and its search bar asks
// for a router.
vi.mock('next/dynamic', () => ({ default: () => () => null }));
vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), refresh: vi.fn(), back: vi.fn() }),
  usePathname: () => '/recherche',
  useSearchParams: () => new URLSearchParams(),
}));

import { RechercheClient } from '../components/discovery/RechercheClient';
import type { Provider } from '../lib/api/providers';
import { emptyTree } from '../lib/localities';
import { providerFixture } from './fixtures';

/// docs/design/consumer-search.md §3.3 (A4w, decision 233): on `/recherche` the count is the
/// server's `total`, and « Afficher plus de salons » reads the next 24 through the same-origin
/// route, appends them without a salon twice, keeps the rows when it fails, and writes the
/// pages read into the address so « Retour » and a reload show the same rows.

const salon = (id: string): Provider => ({
  ...providerFixture,
  id,
  slug: `salon-${id}`,
  name: `Salon ${id}`,
});
const salons = (from: number, to: number) => {
  const out: Provider[] = [];
  for (let i = from; i < to; i++) out.push(salon(`s${String(i).padStart(2, '0')}`));
  return out;
};

type Answer = () => Response;
const json = (status: number, body: unknown): Answer => () =>
  new Response(JSON.stringify(body), { status });

/// The browser's requests, and the BFF's answers to `/api/recherche` in order —
/// `/api/me/favorites` is answered 401 (a guest), as the other search tests do.
function server(...answers: Answer[]) {
  const asked: string[] = [];
  const held: ((r: Response) => void)[] = [];
  let i = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      const u = String(url);
      if (!u.startsWith('/api/recherche')) return new Response(null, { status: 401 });
      asked.push(u);
      const answer = answers[Math.min(i, answers.length - 1)];
      i += 1;
      if (!answer) return new Promise<Response>((resolve) => held.push(resolve));
      return answer();
    }),
  );
  return { asked, held };
}

function page({
  results,
  total,
  pages = 1,
  q = 'tresses',
  commune = 'Cocody',
  category = 'salon',
  sort = 'rating',
  dispo = true,
}: {
  results: Provider[];
  total: number;
  pages?: number;
  q?: string;
  commune?: string;
  category?: string;
  sort?: string;
  dispo?: boolean;
}) {
  return render(
    <RechercheClient
      title="Salons"
      results={results}
      total={total}
      pages={pages}
      q={q}
      commune={commune}
      category={category}
      sort={sort}
      dispo={dispo}
      tree={emptyTree}
    />,
  );
}

const rows = () => screen.getAllByRole('heading', { level: 3 }).map((h) => h.textContent);
const more = () => screen.queryByRole('button', { name: 'Afficher plus de salons' });

let replaced: string[];
beforeEach(() => {
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
  replaced = [];
  vi.spyOn(window.history, 'replaceState').mockImplementation((_s, _t, url) => {
    replaced.push(String(url));
  });
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('the count is the server’s total (§3.3 item 1)', () => {
  it('« 63 salons » over the 24 on the page', () => {
    server();
    page({ results: salons(0, 24), total: 63 });
    expect(rows()).toHaveLength(24);
    expect(screen.getByRole('heading', { level: 2, name: '63 salons' })).toBeInTheDocument();
  });

  it('« 1 salon »', () => {
    server();
    page({ results: salons(0, 1), total: 1 });
    expect(screen.getByRole('heading', { level: 2, name: '1 salon' })).toBeInTheDocument();
  });

  it('nothing found: no count, the empty state says it', () => {
    server();
    page({ results: [], total: 0 });
    expect(screen.queryByRole('heading', { level: 2 })).toBeNull();
    expect(screen.getByText('Aucun salon trouvé')).toBeInTheDocument();
  });
});

describe('« Afficher plus de salons » (§3.3 item 2)', () => {
  it('shown while pages × 24 < total; gone at exactly one full page', () => {
    server();
    page({ results: salons(0, 24), total: 25 });
    expect(more()).toBeInTheDocument();
    cleanup();
    page({ results: salons(0, 24), total: 24 });
    expect(more()).toBeNull();
    cleanup();
    page({ results: salons(0, 3), total: 3 });
    expect(more()).toBeNull();
  });

  it('asks the same-origin route for the next page of the same search', async () => {
    const { asked } = server(json(200, { items: salons(24, 48), page: 2, pageSize: 24, total: 63 }));
    page({ results: salons(0, 24), total: 63 });
    await act(async () => {
      fireEvent.click(more()!);
    });
    expect(asked).toHaveLength(1);
    const u = new URL(asked[0], 'https://myweli.com');
    expect(u.pathname).toBe('/api/recherche');
    expect(Object.fromEntries(u.searchParams)).toEqual({
      q: 'tresses',
      commune: 'Cocody',
      category: 'salon',
      sort: 'rating',
      availableToday: 'true',
      page: '2',
    });
  });

  it('appends the next page without a salon twice, and goes when nothing is left', async () => {
    // s23 again on page 2: a salon unpublished between the two reads shifted the rest by one.
    server(json(200, { items: salons(23, 47), page: 2, pageSize: 24, total: 47 }));
    page({ results: salons(0, 24), total: 47 });
    await act(async () => {
      fireEvent.click(more()!);
    });
    await waitFor(() => expect(rows()).toHaveLength(47));
    expect(new Set(rows()).size).toBe(47);
    expect(screen.getByRole('heading', { level: 2, name: '47 salons' })).toBeInTheDocument();
    expect(more()).toBeNull();
  });

  it('while it loads, the button is busy and the rows stay', async () => {
    const { held } = server(undefined as unknown as Answer);
    page({ results: salons(0, 24), total: 63 });
    act(() => {
      fireEvent.click(more()!);
    });
    const busy = screen.getByRole('button', { name: /Afficher plus de salons|Chargement/ });
    expect(busy).toHaveAttribute('aria-busy', 'true');
    expect(busy).toBeDisabled();
    expect(rows()).toHaveLength(24);
    await act(async () => {
      held[0](new Response(JSON.stringify({ items: salons(24, 48), page: 2, pageSize: 24, total: 63 })));
    });
    await waitFor(() => expect(rows()).toHaveLength(48));
  });

  it('a failed page: « Impossible d’afficher la suite. » and « Réessayer » in its place, the rows kept', async () => {
    const { asked } = server(
      json(502, { error: 'bad_gateway' }),
      json(200, { items: salons(24, 48), page: 2, pageSize: 24, total: 63 }),
    );
    page({ results: salons(0, 24), total: 63 });
    await act(async () => {
      fireEvent.click(more()!);
    });
    expect(await screen.findByText('Impossible d’afficher la suite.')).toBeInTheDocument();
    expect(more()).toBeNull();
    expect(rows()).toHaveLength(24);
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    });
    await waitFor(() => expect(rows()).toHaveLength(48));
    expect(new URL(asked[1], 'https://myweli.com').searchParams.get('page')).toBe('2');
    expect(screen.queryByText('Impossible d’afficher la suite.')).toBeNull();
  });

  it('a 200 without its total is a failure, not a count of 0', async () => {
    server(json(200, { items: salons(24, 48), page: 2, pageSize: 24 }));
    page({ results: salons(0, 24), total: 63 });
    await act(async () => {
      fireEvent.click(more()!);
    });
    expect(await screen.findByText('Impossible d’afficher la suite.')).toBeInTheDocument();
    expect(rows()).toHaveLength(24);
  });

  it('no network: the same failure, not a stuck loader', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        if (String(url).startsWith('/api/recherche')) throw new TypeError('Failed to fetch');
        return new Response(null, { status: 401 });
      }),
    );
    page({ results: salons(0, 24), total: 63 });
    await act(async () => {
      fireEvent.click(more()!);
    });
    expect(await screen.findByText('Impossible d’afficher la suite.')).toBeInTheDocument();
  });
});

describe('after a page lands (§3.3 items 3 and 5)', () => {
  it('the focus is on the first new salon, and the status says how many', async () => {
    server(json(200, { items: salons(24, 48), page: 2, pageSize: 24, total: 63 }));
    page({ results: salons(0, 24), total: 63 });
    await act(async () => {
      fireEvent.click(more()!);
    });
    await waitFor(() => expect(rows()).toHaveLength(48));
    const first = screen.getByRole('heading', { level: 3, name: 'Salon s24' }).closest('a');
    expect(first).toHaveFocus();
    // The toast keeps its own status region; this is the page's.
    const said = screen.getAllByRole('status').map((s) => s.textContent);
    expect(said).toContain('24 salons de plus, 48 sur 63');
  });

  it('the address holds the pages read, so « Retour » and a reload show the same rows', async () => {
    server(
      json(200, { items: salons(24, 48), page: 2, pageSize: 24, total: 63 }),
      json(200, { items: salons(48, 63), page: 3, pageSize: 24, total: 63 }),
    );
    window.history.pushState({}, '', '/recherche?q=tresses&commune=Cocody');
    page({ results: salons(0, 24), total: 63 });
    await act(async () => {
      fireEvent.click(more()!);
    });
    await waitFor(() => expect(rows()).toHaveLength(48));
    expect(replaced.at(-1)).toBe('/recherche?q=tresses&commune=Cocody&pages=2');
    await act(async () => {
      fireEvent.click(more()!);
    });
    await waitFor(() => expect(rows()).toHaveLength(63));
    expect(replaced.at(-1)).toBe('/recherche?q=tresses&commune=Cocody&pages=3');
  });

  it('opened on pages=2, the next tap reads page 3', async () => {
    const { asked } = server(json(200, { items: salons(48, 63), page: 3, pageSize: 24, total: 63 }));
    page({ results: salons(0, 48), total: 63, pages: 2 });
    await act(async () => {
      fireEvent.click(more()!);
    });
    expect(new URL(asked[0], 'https://myweli.com').searchParams.get('page')).toBe('3');
  });

  it('the address stops at pages=10; the button goes on', async () => {
    server(json(200, { items: salons(240, 264), page: 11, pageSize: 24, total: 300 }));
    window.history.pushState({}, '', '/recherche?pages=10');
    page({ results: salons(0, 240), total: 300, pages: 10 });
    await act(async () => {
      fireEvent.click(more()!);
    });
    await waitFor(() => expect(rows()).toHaveLength(264));
    expect(replaced.at(-1)).toBe('/recherche?pages=10');
    expect(more()).toBeInTheDocument();
  });
});

describe('a new search, and a failure, while the rows are long', () => {
  /// The header's search navigates in place (`router.push`): the same client, new props.
  function rerenderWith(view: ReturnType<typeof page>, results: Provider[], total: number) {
    view.rerender(
      <RechercheClient
        title="Salons"
        results={results}
        total={total}
        pages={1}
        q="manucure"
        commune=""
        category=""
        sort="relevance"
        dispo={false}
        tree={emptyTree}
      />,
    );
  }

  it('a new answer from the server is its rows, not the last search’s appended ones', async () => {
    server(json(200, { items: salons(24, 48), page: 2, pageSize: 24, total: 63 }));
    const view = page({ results: salons(0, 24), total: 63 });
    await act(async () => {
      fireEvent.click(more()!);
    });
    await waitFor(() => expect(rows()).toHaveLength(48));
    rerenderWith(view, [salon('m1'), salon('m2')], 2);
    expect(rows()).toEqual(['Salon m1', 'Salon m2']);
    expect(screen.getByRole('heading', { level: 2, name: '2 salons' })).toBeInTheDocument();
    expect(more()).toBeNull();
  });

  it('a page answered after a new search is not that search’s page', async () => {
    const { held } = server(undefined as unknown as Answer);
    const view = page({ results: salons(0, 24), total: 63 });
    act(() => {
      fireEvent.click(more()!);
    });
    rerenderWith(view, [salon('m1')], 1);
    await act(async () => {
      held[0](new Response(JSON.stringify({ items: salons(24, 48), page: 2, pageSize: 24, total: 63 })));
    });
    expect(rows()).toEqual(['Salon m1']);
    expect(replaced).toEqual([]);
  });

  it('a failure puts the focus on « Réessayer » — the button that was pressed is gone', async () => {
    server(json(502, { error: 'bad_gateway' }));
    page({ results: salons(0, 24), total: 63 });
    more()!.focus();
    await act(async () => {
      fireEvent.click(more()!);
    });
    expect(await screen.findByRole('button', { name: 'Réessayer' })).toHaveFocus();
  });
});

it('an older search’s page still out does not hold the new search’s button', async () => {
  const { held, asked } = server(
    undefined as unknown as Answer,
    json(200, { items: salons(124, 148), page: 2, pageSize: 24, total: 63 }),
  );
  const view = page({ results: salons(0, 24), total: 63 });
  act(() => {
    fireEvent.click(more()!);
  });
  view.rerender(
    <RechercheClient
      title="Salons"
      results={salons(100, 124)}
      total={63}
      pages={1}
      q="manucure"
      commune=""
      category=""
      sort="relevance"
      dispo={false}
      tree={emptyTree}
    />,
  );
  await act(async () => {
    fireEvent.click(more()!);
  });
  expect(asked).toHaveLength(2);
  await waitFor(() => expect(rows()).toHaveLength(48));
  expect(rows()[24]).toBe('Salon s124');
  held[0](new Response(JSON.stringify({ items: salons(24, 48), page: 2, pageSize: 24, total: 63 })));
});

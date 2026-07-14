import type { Metadata } from 'next';
import { RechercheClient } from '../../components/discovery/RechercheClient';
import { getLocalityTree } from '../../lib/api/localities';
import { searchProviders } from '../../lib/api/providers';

// Results are query-dependent + thin → render on demand, noindex (the indexed
// SEO targets are the commune×category landings).
export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Recherche',
  robots: { index: false, follow: true },
};

const SORTS = ['relevance', 'rating', 'price'] as const;
type Sort = (typeof SORTS)[number];

export default async function RecherchePage({
  searchParams,
}: {
  searchParams: {
    q?: string;
    commune?: string;
    category?: string;
    sort?: string;
    dispo?: string;
  };
}) {
  const q = searchParams.q ?? '';
  const commune = searchParams.commune ?? '';
  const category = searchParams.category ?? '';
  // Parity 2.1/2.2 — the app's sort (default Pertinence) + availability pill.
  const sort: Sort = (SORTS as readonly string[]).includes(
    searchParams.sort ?? '',
  )
    ? (searchParams.sort as Sort)
    : 'relevance';
  const dispo = searchParams.dispo === '1';

  const [results, tree] = await Promise.all([
    searchProviders({
      q: q || undefined,
      commune: commune || undefined,
      category: category || undefined,
      sort,
      availableToday: dispo || undefined,
      pageSize: 24,
    }),
    getLocalityTree(),
  ]);

  const title = q
    ? `Recherche : ${q}`
    : commune
      ? `Salons à ${commune}`
      : 'Tous les salons';

  return (
    // Full-width — the map is part of the screen (no container box); the
    // search header lives inside the split's left column
    // (docs/design/web-discovery-map.md §2).
    <main>
      <RechercheClient
        title={title}
        results={results}
        q={q}
        commune={commune}
        category={category}
        sort={sort}
        dispo={dispo}
        tree={tree}
      />
    </main>
  );
}

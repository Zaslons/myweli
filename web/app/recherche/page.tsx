import type { Metadata } from 'next';
import { RechercheClient } from '../../components/discovery/RechercheClient';
import { searchProviders } from '../../lib/api/providers';

// Results are query-dependent + thin → render on demand, noindex (the indexed
// SEO targets are the commune×category landings).
export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Recherche',
  robots: { index: false, follow: true },
};

export default async function RecherchePage({
  searchParams,
}: {
  searchParams: { q?: string; commune?: string; category?: string };
}) {
  const q = searchParams.q ?? '';
  const commune = searchParams.commune ?? '';
  const category = searchParams.category ?? '';

  const results = await searchProviders({
    q: q || undefined,
    commune: commune || undefined,
    category: category || undefined,
    pageSize: 24,
  });

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
      />
    </main>
  );
}

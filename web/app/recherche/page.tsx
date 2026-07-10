import type { Metadata } from 'next';
import { RechercheClient } from '../../components/discovery/RechercheClient';
import { HomeSearch } from '../../components/home/HomeSearch';
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
    <main className="mx-auto max-w-7xl px-m py-l">
      <h1 className="text-2xl font-semibold text-textPrimary">{title}</h1>
      <div className="mt-m max-w-3xl">
        <HomeSearch defaultService={q} defaultCommune={commune} />
      </div>
      {/* The split view: list + sticky discovery map
          (docs/design/web-discovery-map.md). */}
      <RechercheClient
        results={results}
        q={q}
        commune={commune}
        category={category}
      />
    </main>
  );
}

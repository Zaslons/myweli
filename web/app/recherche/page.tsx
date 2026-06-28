import type { Metadata } from 'next';
import { HomeSearch } from '../../components/home/HomeSearch';
import { ProviderCard } from '../../components/provider/ProviderCard';
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
    <main className="mx-auto max-w-5xl px-m py-l">
      <h1 className="text-2xl font-semibold text-textPrimary">{title}</h1>
      <div className="mt-m max-w-3xl">
        <HomeSearch defaultService={q} defaultCommune={commune} />
      </div>
      <p className="mt-m text-sm text-textTertiary">
        {results.length} salon{results.length > 1 ? 's' : ''}
      </p>
      <div className="mt-m">
        {results.length === 0 ? (
          <div className="rounded-xl border border-border bg-secondary p-l text-center text-textSecondary">
            Aucun salon trouvé. Essayez une autre recherche ou une autre commune.
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-m sm:grid-cols-2 lg:grid-cols-3">
            {results.map((p) => (
              <ProviderCard key={p.id} provider={p} />
            ))}
          </div>
        )}
      </div>
    </main>
  );
}

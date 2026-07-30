import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import {
  TaxonomyLandingView,
  taxonomyMetadata,
  type TaxonomyInput,
} from '../../../components/landing/TaxonomyLandingView';
import { findCity, getLocalityTree } from '../../../lib/api/localities';
import { resolveTaxonomyRoot, taxonomyRootSlugs } from '../../../lib/taxonomy';

export const revalidate = 3600;
export const dynamicParams = true;

/// City level of the nested SEO tree (/coiffure/abidjan — multi-pays MP3).
/// Valid only when [slug] is a taxonomy root AND [city] is in the locality
/// tree — anything else 404s (provider sub-paths other than the static
/// /reserver don't exist). NB: the literal /​[provider]/reserver route wins
/// over this dynamic segment by Next precedence.
export async function generateStaticParams() {
  const tree = await getLocalityTree();
  const cities = tree.countries.flatMap((c) => c.cities.map((x) => x.slug));
  return taxonomyRootSlugs().flatMap((slug) =>
    cities.map((city) => ({ slug, city })),
  );
}

async function resolve(params: {
  slug: string;
  city: string;
}): Promise<TaxonomyInput | null> {
  const root = resolveTaxonomyRoot(params.slug);
  if (!root) return null;
  const tree = await getLocalityTree();
  const city = findCity(tree, params.city);
  if (!city) return null;
  return { level: 'city', root, city, tree };
}

export async function generateMetadata({
  params,
}: {
  params: { slug: string; city: string };
}): Promise<Metadata> {
  const input = await resolve(params);
  if (!input) return { title: 'Page introuvable' };
  return taxonomyMetadata(input);
}

export default async function CityLandingPage({
  params,
}: {
  params: { slug: string; city: string };
}) {
  const input = await resolve(params);
  if (!input) notFound();
  return <TaxonomyLandingView {...input} />;
}

import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import {
  TaxonomyLandingView,
  taxonomyMetadata,
  type TaxonomyInput,
} from '../../../components/landing/TaxonomyLandingView';
import { findCity, getLocalityTree } from '../../../lib/api/localities';
import { resolveTaxonomyRoot } from '../../../lib/taxonomy';
import { taxonomyCityParams } from '../../../lib/taxonomyParams';

export const revalidate = 3600;
// **false, and that is the 404 fix** — an unknown city never enters this route,
// so Next serves the prerendered 404 instead of the `__next_error__` shell that
// a request-time `notFound()` produces. Safe because `taxonomyCityParams`
// enumerates the complete space from the locality tree.
export const dynamicParams = false;

/// City level of the nested SEO tree (/coiffure/abidjan — multi-pays MP3).
/// Valid only when [slug] is a taxonomy root AND [city] is in the locality
/// tree — anything else 404s (provider sub-paths other than the static
/// /reserver don't exist). NB: the literal /​[provider]/reserver route wins
/// over this dynamic segment by Next precedence.
export async function generateStaticParams() {
  return taxonomyCityParams(await getLocalityTree());
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

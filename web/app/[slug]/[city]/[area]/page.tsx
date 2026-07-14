import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import {
  TaxonomyLandingView,
  taxonomyMetadata,
  type TaxonomyInput,
} from '../../../../components/landing/TaxonomyLandingView';
import {
  findArea,
  findCity,
  getLocalityTree,
} from '../../../../lib/api/localities';
import {
  getLandingParams,
  getServiceLandingParams,
} from '../../../../lib/api/providers';
import { resolveTaxonomyRoot } from '../../../../lib/taxonomy';

export const revalidate = 3600;
export const dynamicParams = true;

/// Area level of the nested SEO tree (/coiffure/abidjan/cocody — multi-pays
/// MP3): the main indexed landing, one per taxonomy root × area. Prebuilds
/// the combos present in the live catalogue; the rest render on demand.
export async function generateStaticParams() {
  const tree = await getLocalityTree();
  const [categories, services] = await Promise.all([
    getLandingParams(tree),
    getServiceLandingParams(tree),
  ]);
  return [...categories, ...services];
}

async function resolve(params: {
  slug: string;
  city: string;
  area: string;
}): Promise<TaxonomyInput | null> {
  const root = resolveTaxonomyRoot(params.slug);
  if (!root) return null;
  const tree = await getLocalityTree();
  const city = findCity(tree, params.city);
  if (!city) return null;
  const area = findArea(city, params.area);
  if (!area) return null;
  return { level: 'area', root, city, area, tree };
}

export async function generateMetadata({
  params,
}: {
  params: { slug: string; city: string; area: string };
}): Promise<Metadata> {
  const input = await resolve(params);
  if (!input) return { title: 'Page introuvable' };
  return taxonomyMetadata(input);
}

export default async function AreaLandingPage({
  params,
}: {
  params: { slug: string; city: string; area: string };
}) {
  const input = await resolve(params);
  if (!input) notFound();
  return <TaxonomyLandingView {...input} />;
}

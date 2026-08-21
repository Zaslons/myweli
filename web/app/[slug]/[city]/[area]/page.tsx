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
import { taxonomyAreaParams } from '../../../../lib/taxonomyParams';

export const revalidate = 3600;
// **false, and that is the 404 fix.** An unknown commune then never enters this
// route: Next serves the prerendered 404 page, 311 characters of real HTML,
// instead of the 44-character `__next_error__` shell a request-time
// `notFound()` produces. Measured — see served-html.spec.ts.
//
// Safe only because `taxonomyAreaParams` enumerates the COMPLETE space from the
// locality tree. The old `generateStaticParams` here asked the catalogue, which
// is empty until a salon opens, so closing the params on THAT would have 404'd
// 187 valid pages — the same defect the sitemap had until 2026-08-20.
export const dynamicParams = false;

/// Area level of the nested SEO tree (/coiffure/abidjan/cocody — multi-pays
/// MP3): the main indexed landing, one per taxonomy root × area. Prebuilds
/// the combos present in the live catalogue; the rest render on demand.
export async function generateStaticParams() {
  return taxonomyAreaParams(await getLocalityTree());
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

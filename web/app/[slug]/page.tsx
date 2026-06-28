import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { LandingView, landingMetadata } from '../../components/landing/LandingView';
import {
  ProviderView,
  providerMetadata,
} from '../../components/provider/ProviderView';
import {
  getAllProviderSlugs,
  getLandingSlugs,
  getProviderBySlug,
} from '../../lib/api/providers';
import { parseLandingSlug } from '../../lib/landing';

export const revalidate = 3600;
export const dynamicParams = true;

/// Single-segment space, resolved provider-first → category·commune landing →
/// 404 (docs/design/web-m4-landing.md). Prebuilds known provider slugs + the
/// landing combos present in the catalogue; others render on-demand.
export async function generateStaticParams() {
  const [slugs, landings] = await Promise.all([
    getAllProviderSlugs(),
    getLandingSlugs(),
  ]);
  return [...new Set([...slugs, ...landings])].map((slug) => ({ slug }));
}

export async function generateMetadata({
  params,
}: {
  params: { slug: string };
}): Promise<Metadata> {
  const provider = await getProviderBySlug(params.slug);
  if (provider) return providerMetadata(provider, params.slug);
  const landing = parseLandingSlug(params.slug);
  if (landing) return landingMetadata(landing, params.slug);
  return { title: 'Page introuvable' };
}

export default async function SlugPage({
  params,
}: {
  params: { slug: string };
}) {
  const provider = await getProviderBySlug(params.slug);
  if (provider) return <ProviderView provider={provider} slug={params.slug} />;

  const landing = parseLandingSlug(params.slug);
  if (landing) return <LandingView landing={landing} slug={params.slug} />;

  notFound();
}

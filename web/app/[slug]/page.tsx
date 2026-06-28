import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { LandingView, landingMetadata } from '../../components/landing/LandingView';
import {
  ServiceLandingView,
  serviceLandingMetadata,
} from '../../components/landing/ServiceLandingView';
import {
  ProviderView,
  providerMetadata,
} from '../../components/provider/ProviderView';
import {
  getAllProviderSlugs,
  getLandingSlugs,
  getProviderBySlug,
  getServiceLandingSlugs,
} from '../../lib/api/providers';
import { parseLandingSlug } from '../../lib/landing';
import { parseServiceLanding } from '../../lib/service-landing';

export const revalidate = 3600;
export const dynamicParams = true;

/// Single-segment space, resolved provider-first → category·commune landing →
/// 404 (docs/design/web-m4-landing.md). Prebuilds known provider slugs + the
/// landing combos present in the catalogue; others render on-demand.
export async function generateStaticParams() {
  const [slugs, landings, serviceLandings] = await Promise.all([
    getAllProviderSlugs(),
    getLandingSlugs(),
    getServiceLandingSlugs(),
  ]);
  return [...new Set([...slugs, ...landings, ...serviceLandings])].map(
    (slug) => ({ slug }),
  );
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
  const service = parseServiceLanding(params.slug);
  if (service) return serviceLandingMetadata(service, params.slug);
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

  const service = parseServiceLanding(params.slug);
  if (service) {
    return <ServiceLandingView landing={service} slug={params.slug} />;
  }

  notFound();
}

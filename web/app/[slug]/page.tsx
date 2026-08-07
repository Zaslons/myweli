import type { Metadata } from 'next';
import { notFound, permanentRedirect } from 'next/navigation';
import {
  TaxonomyLandingView,
  taxonomyMetadata,
} from '../../components/landing/TaxonomyLandingView';
import {
  ProviderView,
  providerMetadata,
} from '../../components/provider/ProviderView';
import { countryName, getLocalityTree } from '../../lib/api/localities';
import {
  getAllProviderSlugs,
  getProviderBySlug,
} from '../../lib/api/providers';
import { parseFlatLanding } from '../../lib/landing';
import { parseFlatServiceLanding } from '../../lib/service-landing';
import { resolveTaxonomyRoot, taxonomyRootSlugs } from '../../lib/taxonomy';

// **300, not 3600, since PR1d.** Decision C closes the API to a salon that is
// `draft` or `suspended`, but an already-generated page keeps serving from the
// ISR cache until its window expires — T51's promise defeated by a stale file.
// Five minutes bounds it; on-demand revalidation on the four write sites is its
// own slice. Note the asymmetry: `[slug]/reserver` is `force-dynamic`, so the
// FUNNEL closes instantly and only the marketing page lags.
//
// It also bounds a defect nobody had written down: `getProviderBySlug`
// collapses 5xx and network failures into `null` too, so a 30-second backend
// blip cached a 404 for a LIVE salon for the whole window (§9).
export const revalidate = 300;
export const dynamicParams = true;

/// Single-segment space (multi-pays MP3): taxonomy ROOT (/coiffure, /tresses
/// — safe first: the backend reserves these slugs, no salon can own one) →
/// provider → LEGACY flat landing (coiffure-cocody) permanently redirected
/// (308 ≡ 301 for SEO) to its nested home → 404. Prebuilds provider slugs +
/// the 18 roots; others render on demand.
export async function generateStaticParams() {
  const slugs = await getAllProviderSlugs();
  return [...new Set([...slugs, ...taxonomyRootSlugs()])].map((slug) => ({
    slug,
  }));
}

/// The nested path a LEGACY flat slug 308s to, or null.
async function flatRedirectTarget(slug: string): Promise<string | null> {
  const tree = await getLocalityTree();
  return parseFlatLanding(slug, tree) ?? parseFlatServiceLanding(slug, tree);
}

export async function generateMetadata({
  params,
}: {
  params: { slug: string };
}): Promise<Metadata> {
  const root = resolveTaxonomyRoot(params.slug);
  if (root) {
    return taxonomyMetadata({ level: 'root', root, tree: await getLocalityTree() });
  }
  const provider = await getProviderBySlug(params.slug);
  if (provider) {
    const tree = await getLocalityTree();
    return providerMetadata(
      provider,
      params.slug,
      countryName(tree, provider.countryCode),
    );
  }
  if (await flatRedirectTarget(params.slug)) {
    return { robots: { index: false, follow: true } };
  }
  return { title: 'Page introuvable' };
}

export default async function SlugPage({
  params,
}: {
  params: { slug: string };
}) {
  const root = resolveTaxonomyRoot(params.slug);
  if (root) {
    const tree = await getLocalityTree();
    return <TaxonomyLandingView level="root" root={root} tree={tree} />;
  }

  const provider = await getProviderBySlug(params.slug);
  if (provider) {
    const tree = await getLocalityTree();
    return (
      <ProviderView
        provider={provider}
        slug={params.slug}
        countryName={countryName(tree, provider.countryCode)}
      />
    );
  }

  const target = await flatRedirectTarget(params.slug);
  if (target) permanentRedirect(target);

  notFound();
}

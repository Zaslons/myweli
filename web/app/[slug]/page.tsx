import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
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
// **false, and that is the 404 fix.** An unknown slug then never enters this
// route, so Next serves the prerendered 404 — 311 characters of real HTML —
// instead of the 44-character `__next_error__` shell a request-time
// `notFound()` produces. Measured; see served-html.spec.ts for what was ruled
// out.
//
// It also means a salon approved after the last build is not reachable until
// the next one, which is why admin KYC approval fires a rebuild.
export const dynamicParams = false;

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

  // Unreachable with the params closed — an unlisted slug never gets here, and
  // the legacy flat landings now 308 from `next.config.mjs` before routing.
  // Kept as a belt-and-braces refusal rather than a silent fallthrough.
  notFound();
}

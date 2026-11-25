import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import {
  ProviderView,
  providerMetadata,
} from '../../../../components/provider/ProviderView';
import { countryName, getLocalityTree } from '../../../../lib/api/localities';
import { getProviderBySlug } from '../../../../lib/api/providers';

/// The salon page, rendered live for a salon that is public but not yet in this
/// build. Design: docs/design/web-salon-page-live-fallback.md §3.3.
///
/// **Nobody reaches this path by its name.** `middleware.ts` rewrites
/// `/<slug>` here once the API says the salon is public, so the browser keeps
/// the salon's own address and the canonical (`providerMetadata`) is
/// `/<slug>`: this IS the salon's page, a few minutes before the rebuild serves
/// it statically. A request naming this path is rewritten to the real 404.
///
/// It draws exactly what `app/[slug]/page.tsx` draws for a salon. If the salon
/// stops being public between the middleware's read and this one (a window of
/// milliseconds), `notFound()` answers 404 with the blank-until-JS body of a
/// request-time 404 (served-html.spec.ts). An accepted residual, written down
/// in the spec.
export const dynamic = 'force-dynamic';

export async function generateMetadata({
  params,
}: {
  params: { slug: string };
}): Promise<Metadata> {
  const provider = await getProviderBySlug(params.slug);
  if (!provider) return { title: 'Page introuvable' };
  const tree = await getLocalityTree();
  return providerMetadata(provider, params.slug, countryName(tree, provider.countryCode));
}

export default async function LiveSalonPage({
  params,
}: {
  params: { slug: string };
}) {
  const provider = await getProviderBySlug(params.slug);
  if (!provider) notFound();
  const tree = await getLocalityTree();
  return (
    <ProviderView
      provider={provider}
      slug={params.slug}
      countryName={countryName(tree, provider.countryCode)}
    />
  );
}

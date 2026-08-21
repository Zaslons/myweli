import type { Metadata } from 'next';
import { redirect } from 'next/navigation';

import { BookingFlow } from '../../../components/booking/BookingFlow';
import { countryName, getLocalityTree } from '../../../lib/api/localities';
import { getProviderBySlug } from '../../../lib/api/providers';
import { categoryLabelFr } from '../../../lib/seo/jsonld';

// Interactive + authed funnel — not prerendered, not indexed.
export const dynamic = 'force-dynamic';

export async function generateMetadata({
  params,
}: {
  params: { slug: string };
}): Promise<Metadata> {
  const p = await getProviderBySlug(params.slug);
  return {
    title: p ? `Réserver — ${p.name}` : 'Réserver',
    robots: { index: false, follow: true },
  };
}

export default async function ReserverPage({
  params,
  searchParams,
}: {
  params: { slug: string };
  searchParams: { services?: string; artist?: string };
}) {
  const p = await getProviderBySlug(params.slug);
  // **Hand the 404 to `/[slug]`, which serves a real one.**
  //
  // `notFound()` here cannot: this page reads `searchParams`, so it renders
  // per-request, and a dynamically-rendered route does not enforce
  // `dynamicParams = false` — measured both ways, and a segment `layout.tsx`
  // carrying the bound does not gate it either. Giving up `searchParams` WOULD
  // fix it, at the cost of this funnel's server-rendered service list
  // (« Tresses 15 000 – 25 000 FCFA … »), which is exactly the content a slow
  // phone needs. So the visitor goes one segment up, where the params ARE
  // closed. 307, not 308 — a slug with no salon today may have one tomorrow.
  if (!p) redirect(`/${params.slug}`);
  // The salon-time hint's country label (multi-pays MP3) — tree lookup on
  // the salon's own countryCode, server-side.
  const country = countryName(await getLocalityTree(), p.countryCode);

  // Rebook prefill (?services=a,b&artist=x) — sanitized against the live
  // catalogue inside the hub, so stale ids are silently dropped.
  const prefillServiceIds = (searchParams.services ?? '')
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean)
    .slice(0, 20);
  const prefillArtistId = searchParams.artist?.trim() || null;

  return (
    <main className="mx-auto max-w-2xl px-m py-l lg:max-w-5xl">
      <h1 className="text-headlineSmall font-semibold text-textPrimary">
        Réserver chez {p.name}
      </h1>
      <p className="mt-xs text-bodyMedium text-textTertiary">
        {categoryLabelFr(p.category)}
        {p.commune ? ` · ${p.commune}` : ''}
      </p>
      <div className="mt-l">
        <BookingFlow
          provider={p}
          prefillServiceIds={prefillServiceIds}
          prefillArtistId={prefillArtistId}
          countryLabel={country}
        />
      </div>
    </main>
  );
}

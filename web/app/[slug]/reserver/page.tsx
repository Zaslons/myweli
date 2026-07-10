import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { BookingFlow } from '../../../components/booking/BookingFlow';
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
  if (!p) notFound();

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
      <h1 className="text-2xl font-semibold text-textPrimary">
        Réserver chez {p.name}
      </h1>
      <p className="mt-xs text-sm text-textTertiary">
        {categoryLabelFr(p.category)}
        {p.commune ? ` · ${p.commune}` : ''}
      </p>
      <div className="mt-l">
        <BookingFlow
          provider={p}
          prefillServiceIds={prefillServiceIds}
          prefillArtistId={prefillArtistId}
        />
      </div>
    </main>
  );
}

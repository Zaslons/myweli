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
}: {
  params: { slug: string };
}) {
  const p = await getProviderBySlug(params.slug);
  if (!p) notFound();

  return (
    <main className="mx-auto max-w-2xl px-m py-l">
      <h1 className="text-2xl font-semibold text-textPrimary">
        Réserver chez {p.name}
      </h1>
      <p className="mt-xs text-sm text-textTertiary">
        {categoryLabelFr(p.category)}
        {p.commune ? ` · ${p.commune}` : ''}
      </p>
      <div className="mt-l">
        <BookingFlow provider={p} />
      </div>
    </main>
  );
}

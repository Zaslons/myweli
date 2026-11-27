import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { RevenueDetailClient } from '../../../../../../components/pro/RevenueDetailClient';
import { NO_ARTIST, isRevenueId } from '../../../../../../lib/pro/revenue';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Revenus · collaborateur',
  robots: { index: false, follow: false },
};

/// A collaborateur's revenue (docs/design/pro-revenue-analytics.md §5.2).
/// `none` is the server's word for « Sans collaborateur attribué ».
export default function ProRevenueArtistPage({ params }: { params: { artistId: string } }) {
  const id = params.artistId;
  if (id !== NO_ARTIST && !isRevenueId(id)) notFound();
  return (
    <div className="max-w-5xl">
      <RevenueDetailClient axis="artist" filterKey={id} />
    </div>
  );
}

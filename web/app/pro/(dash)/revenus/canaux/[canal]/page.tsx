import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { RevenueDetailClient } from '../../../../../../components/pro/RevenueDetailClient';
import { channelFromSlug } from '../../../../../../lib/pro/revenue';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Revenus · canal',
  robots: { index: false, follow: false },
};

/// A channel's revenue (docs/design/pro-revenue-analytics.md §5.2): the
/// address says it in French — `application` · `site` · `salon` · `en-ligne`.
export default function ProRevenueChannelPage({ params }: { params: { canal: string } }) {
  const channel = channelFromSlug(params.canal);
  if (!channel) notFound();
  return (
    <div className="max-w-5xl">
      <RevenueDetailClient axis="channel" filterKey={channel} />
    </div>
  );
}

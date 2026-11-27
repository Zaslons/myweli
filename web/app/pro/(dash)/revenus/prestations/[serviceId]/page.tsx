import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { RevenueDetailClient } from '../../../../../../components/pro/RevenueDetailClient';
import { isRevenueId } from '../../../../../../lib/pro/revenue';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Revenus · prestation',
  robots: { index: false, follow: false },
};

/// A prestation's revenue (docs/design/pro-revenue-analytics.md §5.2): its
/// lines only — a two-prestation booking adds its line, not its total (§4.8).
export default function ProRevenueServicePage({ params }: { params: { serviceId: string } }) {
  const id = params.serviceId;
  if (!isRevenueId(id)) notFound();
  return (
    <div className="max-w-5xl">
      <RevenueDetailClient axis="service" filterKey={id} />
    </div>
  );
}

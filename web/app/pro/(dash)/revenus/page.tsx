import type { Metadata } from 'next';
import { RevenusClient } from '../../../../components/pro/RevenusClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Revenus',
  robots: { index: false, follow: false },
};

/// docs/design/pro-revenue-analytics.md §5 (R4). The period, the tab and the
/// sort live in the address (§5.2): `?periode=semaine&date=…&comparer=…`.
export default function ProRevenusPage() {
  // The tables' width (§5.1): every state (skeleton, error, success) shares
  // the cap, so nothing flashes full-bleed then snaps.
  return (
    <div className="max-w-5xl">
      <RevenusClient />
    </div>
  );
}

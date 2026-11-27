import type { Metadata } from 'next';
import { RevenueLedgerClient } from '../../../../../components/pro/RevenueLedgerClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Revenus · rendez-vous',
  robots: { index: false, follow: false },
};

/// The bookings behind the figures (docs/design/pro-revenue-analytics.md
/// §4.9, §5.2): the period, the filters and the status in the address.
export default function ProRevenueLedgerPage() {
  return (
    <div className="max-w-5xl">
      <RevenueLedgerClient />
    </div>
  );
}

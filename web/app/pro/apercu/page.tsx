import type { Metadata } from 'next';
import { SalonPreviewClient } from '../../../components/pro/SalonPreviewClient';

// Owner-only preview of the consumer page — outside the (dash) group so the
// consumer chrome (no sidebar) matches what a client actually sees.
export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Aperçu de ma page',
  robots: { index: false, follow: false },
};

export default function ProApercuPage() {
  return <SalonPreviewClient />;
}

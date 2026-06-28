import type { Metadata } from 'next';
import { MediasClient } from '../../../../components/pro/MediasClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Médias',
  robots: { index: false, follow: false },
};

export default function ProMediasPage() {
  return <MediasClient />;
}

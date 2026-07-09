import type { Metadata } from 'next';
import { ClientCardClient } from '../../../../../components/pro/ClientCardClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Fiche client',
  robots: { index: false, follow: false },
};

export default function ProClientCardPage({
  params,
}: {
  params: { clientId: string };
}) {
  return <ClientCardClient clientId={params.clientId} />;
}

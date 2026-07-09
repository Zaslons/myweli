import type { Metadata } from 'next';
import { ClientsClient } from '../../../../components/pro/ClientsClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Clients',
  robots: { index: false, follow: false },
};

export default function ProClientsPage() {
  return <ClientsClient />;
}

import type { Metadata } from 'next';
import { ProAppointmentDetailClient } from '../../../../../components/pro/ProAppointmentDetailClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Pro — Détails du rendez-vous',
  robots: { index: false, follow: false },
};

export default function ProAppointmentPage({
  params,
}: {
  params: { id: string };
}) {
  return <ProAppointmentDetailClient id={params.id} />;
}

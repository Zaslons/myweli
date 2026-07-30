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
  // B7 (§9/§10): the desktop cap — every state (skeleton, error,
  // success) shares it, so nothing flashes full-bleed then snaps.
  return (
    <div className="max-w-content">
      <ProAppointmentDetailClient id={params.id} />
    </div>
  );
}

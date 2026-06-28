import type { Metadata } from 'next';
import { AppointmentDetailClient } from '../../../components/account/AppointmentDetailClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Rendez-vous',
  robots: { index: false, follow: false },
};

export default function AppointmentPage({
  params,
}: {
  params: { id: string };
}) {
  return (
    <main className="mx-auto max-w-2xl px-m py-l">
      <AppointmentDetailClient id={params.id} />
    </main>
  );
}

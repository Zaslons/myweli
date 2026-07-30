import type { Metadata } from 'next';
import { NotificationsClient } from '../../../components/account/NotificationsClient';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Notifications',
  robots: { index: false, follow: false },
};

export default function NotificationsPage() {
  return (
    <main className="mx-auto max-w-2xl px-m py-l">
      <NotificationsClient />
    </main>
  );
}
